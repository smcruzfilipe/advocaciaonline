class DashboardSnapshot
  TIMEZONE = "America/Sao_Paulo".freeze

  # Read only inside DatabaseContext.with_session after authorize_session! has
  # locked the current membership and resolved its groups. No numeric snapshot
  # or authorization decision is cached between requests.
  def self.call(context:, groups:, now: Time.current)
    new(context: context, groups: groups, now: now).call
  end

  def initialize(context:, groups:, now:)
    @context = context
    @groups = groups
    @now = now.in_time_zone(TIMEZONE)
    @connection = ApplicationRecord.connection
  end

  def call
    permitted = allowed?("consultar_dashboard")
    rows = permitted ? court_states : states_without_metrics
    # A later failed, interrupted or empty plan cannot inherit an earlier
    # slot's successful work as if the latest plan had completed.
    if rows.first && rows.first.fetch("planning_status") != "planned"
      latest_slot = rows.first.fetch("slot")
      rows = rows.select { |row| row.fetch("slot") == latest_slot }
    end
    courts = readable_courts(rows)
    completed = courts.select { |court| court.fetch("state") == "succeeded" }.map { |court| court.fetch("court") }
    counts = metrics(completed) if permitted && completed.any?
    periods = starts.to_h do |name, start|
      values = if !permitted
        ["*", "*"]
      elsif counts
        [counts.fetch("#{name}_communications"), counts.fetch("#{name}_processes")]
      else
        [nil, nil]
      end
      [name, { start: start.iso8601(6), end: @now.iso8601(6), communications: values[0], processes: values[1] }]
    end

    {
      timezone: TIMEZONE,
      as_of: @now.iso8601(6),
      state: permitted ? aggregate_state(courts, rows) : "masked",
      periods: periods,
      courts: courts.map { |court| court.slice("court", "state") },
      warnings: failure_warnings
    }
  end

  private

  def allowed?(operation, court: nil)
    AuthorizationPolicy.allowed?(owner: @context.fetch("role") == "owner", groups: @groups,
      operation: operation, court: court)
  end

  def starts
    @starts ||= {
      "today" => @now.beginning_of_day,
      "week" => @now.beginning_of_week(:monday).beginning_of_day,
      "last_seven_days" => (@now.to_date - 6).in_time_zone(TIMEZONE)
    }
  end

  def court_states
    # collection_court_states is SECURITY INVOKER and keeps runtime's tenant RLS.
    # Its internal publication aggregates are allowed only with dashboard access.
    @connection.exec_query(<<~SQL, "Dashboard court states", binds(@now.to_date.iso8601)).to_a
      SELECT run.status AS planning_status, run.slot, summary.court, summary.state,
        COALESCE(summary.failed_count > 0, false) AS has_failure
      FROM app_private.collection_runs_for_session() AS run
      LEFT JOIN LATERAL app_private.collection_court_states(run.id) AS summary ON true
      WHERE run.collection_date = $1::date
      ORDER BY run.slot DESC, summary.court
    SQL
  end

  def states_without_metrics
    # The existing function also computes publication totals internally. Do not
    # invoke it for a denied dashboard, even when projecting only court/state.
    # This is its state matrix using booleans, with no publications or counts.
    @connection.exec_query(<<~SQL, "Dashboard nonnumeric court states", binds(@now.to_date.iso8601)).to_a
      WITH runs AS (
        SELECT id, slot, status FROM app_private.collection_runs_for_session()
        WHERE collection_date = $1::date
      ), work AS (
        SELECT job.run_id, job.court,
          CASE WHEN execution.state = 'succeeded' AND result.job_id IS NOT NULL THEN 'succeeded'
            WHEN execution.state = 'failed' THEN 'failed' ELSE 'pending' END AS state
        FROM public.collection_jobs AS job JOIN runs ON runs.id = job.run_id
        JOIN public.collection_job_executions AS execution
          ON execution.job_id = job.id AND execution.tenant_id = job.tenant_id
        LEFT JOIN public.collection_job_results AS result
          ON result.job_id = job.id AND result.tenant_id = job.tenant_id
      ), summaries AS (
        SELECT run_id, court, CASE
          WHEN bool_and(state = 'succeeded') THEN 'succeeded'
          WHEN bool_or(state = 'succeeded') THEN 'partial'
          WHEN bool_or(state = 'pending') THEN 'running'
          ELSE 'failed' END AS state,
          bool_or(state = 'failed') AS has_failure
        FROM work GROUP BY run_id, court
      )
      SELECT runs.status AS planning_status, runs.slot, summaries.court, summaries.state,
        COALESCE(summaries.has_failure, false) AS has_failure
      FROM runs LEFT JOIN summaries ON summaries.run_id = runs.id
      ORDER BY runs.slot DESC, summaries.court
    SQL
  end

  def failure_warnings
    # A failed slot stays visible until a later slot of that same day fully
    # succeeds for the court; tomorrow's success cannot recover yesterday.
    @connection.exec_query(<<~SQL, "Dashboard failure warnings", binds(@now.to_date.iso8601)).filter_map do |row|
      WITH runs AS (
        SELECT id, collection_date, slot FROM app_private.collection_runs_for_session()
        WHERE collection_date <= $1::date AND status = 'planned'
      ), summaries AS (
        SELECT runs.collection_date, runs.slot, job.court,
          bool_or(execution.state = 'failed') AS has_failure,
          bool_and(execution.state = 'succeeded' AND result.job_id IS NOT NULL) AS succeeded
        FROM runs JOIN public.collection_jobs AS job ON job.run_id = runs.id
        JOIN public.collection_job_executions AS execution
          ON execution.job_id = job.id AND execution.tenant_id = job.tenant_id
        LEFT JOIN public.collection_job_results AS result
          ON result.job_id = job.id AND result.tenant_id = job.tenant_id
        GROUP BY runs.collection_date, runs.slot, job.court
      )
      SELECT DISTINCT failed.court FROM summaries AS failed
      WHERE failed.has_failure AND NOT EXISTS (
        SELECT 1 FROM summaries AS recovered
        WHERE recovered.collection_date = failed.collection_date AND recovered.court = failed.court
          AND recovered.slot > failed.slot AND recovered.succeeded
      ) ORDER BY failed.court
    SQL
      court = row.fetch("court")
      { court: court, code: "collection_failed" } if allowed?("consultar_comunicacoes", court: court)
    end
  end

  def readable_courts(rows)
    # Latest relevant execution of the local day wins independently per court.
    # A successful second slot recovers the current view, not the first slot's
    # history. A later pending/failed slot must not inherit an earlier success.
    current = {}
    rows.each do |row|
      court = row.fetch("court")
      next if court.nil? || current.key?(court) || !allowed?("consultar_comunicacoes", court: court)

      planned = row.fetch("planning_status") == "planned"
      current[court] = {
        "court" => court,
        "state" => planned ? row.fetch("state") : "unavailable",
        "has_failure" => planned && row.fetch("has_failure")
      }
    end
    current.values.sort_by { |court| court.fetch("court") }
  end

  def aggregate_state(courts, rows)
    states = courts.map { |court| court.fetch("state") }
    return "succeeded" if states.any? && states.all? { |state| state == "succeeded" }
    return "partial" if states.include?("succeeded") || states.include?("partial")
    return "running" if states.include?("running")
    return "failed" if states.include?("failed")

    # No readable tribunal is not evidence that collection was empty. Only a
    # tenant-visible plan with no jobs can establish no_work, still without zero.
    latest = rows.first
    return "no_work" if latest && rows.all? { |row| row.fetch("court").nil? } &&
      %w[planned no_work].include?(latest.fetch("planning_status"))

    "unavailable"
  end

  def metrics(completed)
    # Resolve the first payload's court before filtering; later links cannot
    # authorize it. A conflicting source court also requires read permission.
    source_courts = @connection.exec_query(<<~SQL, "Dashboard source tribunals", binds(@context.fetch("tenant_id"))).filter_map do |row|
      SELECT DISTINCT payload->>'siglaTribunal' AS court
      FROM public.collection_communications
      WHERE tenant_id = $1::uuid AND jsonb_typeof(payload->'siglaTribunal') = 'string'
    SQL
      court = row.fetch("court")
      court if allowed?("consultar_comunicacoes", court: court)
    end
    parameters = binds(@context.fetch("tenant_id"),
      starts.fetch("last_seven_days").utc.iso8601(6), @now.utc.iso8601(6),
      starts.fetch("today").utc.iso8601(6), starts.fetch("week").utc.iso8601(6),
      JSON.generate(completed), JSON.generate(source_courts))
    @connection.exec_query(<<~SQL, "Dashboard metrics", parameters).first
      WITH candidates AS MATERIALIZED (
        SELECT id, tenant_id, payload, recorded_at
        FROM public.collection_communications
        WHERE tenant_id = $1::uuid AND source = 'DJEN' AND identity_status = 'complete'
          AND recorded_at >= $2::timestamptz AND recorded_at < $3::timestamptz
      ), origins AS (
        SELECT candidate.id, min(job.court) AS court
        FROM candidates AS candidate
        JOIN LATERAL (
          SELECT min(link.recorded_at) AS recorded_at
          FROM public.collection_communication_links AS link
          WHERE link.communication_id = candidate.id AND link.tenant_id = candidate.tenant_id
        ) AS first_link ON true
        JOIN public.collection_communication_links AS link
          ON link.communication_id = candidate.id AND link.tenant_id = candidate.tenant_id
          AND link.recorded_at = first_link.recorded_at
        JOIN public.collection_jobs AS job ON job.id = link.job_id AND job.tenant_id = link.tenant_id
        GROUP BY candidate.id
        HAVING count(DISTINCT job.court) = 1
      ), qualified AS (
        SELECT candidate.recorded_at,
          CASE WHEN jsonb_typeof(candidate.payload -> 'numero_processo') = 'string' AND (
            (length(candidate.payload ->> 'numero_processo') = 20 AND
              candidate.payload ->> 'numero_processo' ~ '^[0-9]{20}$') OR
            (length(candidate.payload ->> 'numero_processo') = 25 AND
              candidate.payload ->> 'numero_processo' ~ '^[0-9]{7}-[0-9]{2}[.][0-9]{4}[.][0-9][.][0-9]{2}[.][0-9]{4}$')
          ) THEN translate(candidate.payload ->> 'numero_processo', '-.', '') END AS process_number
        FROM candidates AS candidate JOIN origins ON origins.id = candidate.id
        WHERE origins.court IN (SELECT jsonb_array_elements_text($6::jsonb))
          AND (jsonb_typeof(candidate.payload->'siglaTribunal') IS DISTINCT FROM 'string'
            OR candidate.payload->>'siglaTribunal' !~ '^[A-Za-z][A-Za-z0-9]{1,31}$'
            OR candidate.payload->>'siglaTribunal' = origins.court
            OR candidate.payload->>'siglaTribunal' IN (SELECT jsonb_array_elements_text($7::jsonb)))
      )
      SELECT count(*) FILTER (WHERE recorded_at >= $4::timestamptz) AS today_communications,
        count(DISTINCT process_number) FILTER (WHERE recorded_at >= $4::timestamptz) AS today_processes,
        count(*) FILTER (WHERE recorded_at >= $5::timestamptz) AS week_communications,
        count(DISTINCT process_number) FILTER (WHERE recorded_at >= $5::timestamptz) AS week_processes,
        count(*) AS last_seven_days_communications,
        count(DISTINCT process_number) AS last_seven_days_processes
      FROM qualified
    SQL
  end

  def binds(*values)
    values.each_with_index.map do |value, index|
      ActiveRecord::Relation::QueryAttribute.new("argument_#{index}", value, ActiveRecord::Type::String.new)
    end
  end
end
