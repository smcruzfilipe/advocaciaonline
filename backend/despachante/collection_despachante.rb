require "date"
require "json"
require "pg"
require "tzinfo"
require_relative "../app/services/court_catalog"

class CollectionDespachante
  class InvalidProfile < StandardError; end
  class DayExpired < StandardError; end
  private_constant :DayExpired

  TIME_ZONE = TZInfo::Timezone.get("America/Sao_Paulo")
  FINAL_STATUSES = %w[planned no_work interrupted].freeze

  def initialize(url:)
    @url = url
  end

  def plan(slot:, now:, catalog: -> { CourtCatalog.fetch })
    raise ArgumentError, "A coleta aceita somente os slots 1 e 2." unless slot.is_a?(Integer) && [1, 2].include?(slot)
    date = TIME_ZONE.to_local(now).to_date
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    clock = -> { now + (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) }

    PG.connect(@url) do |connection|
      assert_despachante!(connection)
      existing = connection.exec_params(<<~SQL, [date, slot]).first
        SELECT id, status FROM public.collection_runs WHERE collection_date = $1 AND slot = $2
      SQL
      next existing.fetch("id") if existing && FINAL_STATUSES.include?(existing.fetch("status"))

      # The external catalog is resolved before acquiring database locks.
      courts = nil
      source_failure = nil
      if current_day?(date, clock)
        begin
          courts = catalog.call.map { |court| court.fetch(:code) }.uniq
        rescue StandardError => error
          source_failure = error
        end
      end
      persist_plan(connection, date, slot, courts, source_failure, clock)
    end
  end

  def interrupt_before(now:)
    date = TIME_ZONE.to_local(now).to_date
    PG.connect(@url) do |connection|
      assert_despachante!(connection)
      connection.exec_params(<<~SQL, [date])
        UPDATE public.collection_runs SET status = 'interrupted', updated_at = CURRENT_TIMESTAMP
        WHERE collection_date < $1 AND status = 'planning_failed'
      SQL
    end
  end

  private

  def assert_despachante!(connection)
    safe = connection.exec(<<~SQL).getvalue(0, 0)
      SELECT current_user = 'advocacia_despachante' AND session_user = current_user
        AND rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb
        AND NOT rolcreaterole AND NOT rolreplication
        AND NOT EXISTS (SELECT 1 FROM pg_auth_members WHERE member = pg_roles.oid)
        AND NOT pg_has_role('advocacia_runtime', current_user, 'MEMBER')
      FROM pg_roles WHERE rolname = current_user
    SQL
    raise SecurityError, "O planejamento exige o login isolado advocacia_despachante." unless safe == "t"
  end

  def persist_plan(connection, date, slot, courts, source_failure, clock)
    failure = nil
    id = connection.transaction do
      connection.exec("SET TRANSACTION ISOLATION LEVEL READ COMMITTED")
      # Each subsequent READ COMMITTED statement sees the winning committed insert.
      # https://www.postgresql.org/docs/18/sql-insert.html#SQL-ON-CONFLICT
      inserted = connection.exec_params(<<~SQL, [date, slot])
        INSERT INTO public.collection_runs (collection_date, slot, status)
        VALUES ($1, $2, 'planning_failed') ON CONFLICT (collection_date, slot) DO NOTHING
        RETURNING id
      SQL
      run = connection.exec_params(<<~SQL, [date, slot]).first
        SELECT id, status, audience_fixed FROM public.collection_runs
        WHERE collection_date = $1 AND slot = $2 FOR UPDATE
      SQL
      next run.fetch("id") if FINAL_STATUSES.include?(run.fetch("status"))
      if inserted.any?
        fix_audience(connection, run.fetch("id"))
      elsif run.fetch("audience_fixed") != "t"
        failure = InvalidProfile.new("A audiência original desta execução não foi registrada.")
        next run.fetch("id")
      end

      connection.exec("SAVEPOINT planning_work")
      begin
        ensure_current_day!(date, clock)
        raise source_failure if source_failure
        work = snapshot_work(connection, run.fetch("id"), courts)
        ensure_current_day!(date, clock)
        insert_work(connection, run.fetch("id"), work) unless work.empty?
        update_status(connection, run.fetch("id"), work.empty? ? "no_work" : "planned")
        # Keep the savepoint through this final publication check; COMMIT releases it.
        # https://www.postgresql.org/docs/18/tutorial-transactions.html
        ensure_current_day!(date, clock)
      rescue DayExpired
        connection.exec("ROLLBACK TO SAVEPOINT planning_work")
        update_status(connection, run.fetch("id"), "interrupted")
        failure = source_failure
      rescue StandardError => error
        connection.exec("ROLLBACK TO SAVEPOINT planning_work")
        update_status(connection, run.fetch("id"), current_day?(date, clock) ? "planning_failed" : "interrupted")
        failure = error
      end
      run.fetch("id")
    end
    raise failure if failure
    id
  end

  def current_day?(date, clock)
    date == TIME_ZONE.to_local(clock.call).to_date
  end

  def ensure_current_day!(date, clock)
    raise DayExpired unless current_day?(date, clock)
  end

  def update_status(connection, run_id, status)
    connection.exec_params(<<~SQL, [status, run_id])
      UPDATE public.collection_runs SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2
    SQL
  end

  def fix_audience(connection, run_id)
    # Keep this outside planning_work: a catalog/profile failure retains the
    # known audience, while an audience write failure rolls back the entire run.
    connection.exec_params(<<~SQL, [run_id])
      INSERT INTO public.collection_run_audiences (run_id, tenant_id)
        SELECT $1::uuid, id FROM public.tenants
    SQL
    connection.exec_params("UPDATE public.collection_runs SET audience_fixed = true WHERE id = $1", [run_id])
  end

  def snapshot_work(connection, run_id, courts)
    # All eligibility, ownership and search fields share ONE PostgreSQL statement snapshot.
    # No later registry read can mix a concurrent edit into these frozen criteria.
    # https://www.postgresql.org/docs/18/transaction-iso.html#XACT-READ-COMMITTED
    entities = connection.exec_params(<<~SQL, [run_id])
      WITH audience AS (
        SELECT tenant_id FROM public.collection_run_audiences WHERE run_id = $1
      ), profiles AS (
        SELECT tenant.id AS tenant_id, lawyer.id AS lawyer_id, lawyer.full_name,
          registrations.oabs, registrations.primary_count
        FROM public.tenants AS tenant
        JOIN audience ON audience.tenant_id = tenant.id
        LEFT JOIN public.lawyers AS lawyer ON lawyer.tenant_id = tenant.id
        LEFT JOIN LATERAL (
          SELECT COALESCE(jsonb_agg(jsonb_build_object('number', number, 'uf', uf)
              ORDER BY number, uf), '[]'::jsonb) AS oabs,
            count(*) FILTER (WHERE "primary") AS primary_count
          FROM public.oab_registrations
          WHERE tenant_id = tenant.id AND lawyer_id = lawyer.id
        ) AS registrations ON true
      )
      SELECT tenant_id, 'lawyer' AS entity_type, lawyer_id AS entity_id,
        jsonb_build_object('name', full_name, 'oabs', oabs)::text AS criteria,
        NULL::text AS courts, (lawyer_id IS NOT NULL AND primary_count = 1) AS valid
      FROM profiles
      UNION ALL
      SELECT tenant_id, 'party', id, jsonb_build_object('name', name)::text, to_json(courts)::text, true
      FROM public.party_monitorings WHERE active AND tenant_id IN (SELECT tenant_id FROM audience)
      UNION ALL
      SELECT tenant_id, 'process', id, jsonb_build_object('number', number)::text, to_json(courts)::text, true
      FROM public.process_monitorings WHERE active AND tenant_id IN (SELECT tenant_id FROM audience)
    SQL
    if entities.any? { |entity| entity.fetch("valid") != "t" }
      raise InvalidProfile, "Não foi possível resolver um perfil profissional completo para o planejamento."
    end

    entities.flat_map do |entity|
      selection = entity.fetch("courts") && JSON.parse(entity.fetch("courts"))
      applicable = selection ? selection & courts : courts
      criteria = JSON.parse(entity.fetch("criteria"))
      applicable.product(%w[D E]).map do |court, medium|
        { tenant_id: entity.fetch("tenant_id"), entity_type: entity.fetch("entity_type"),
          entity_id: entity.fetch("entity_id"), source: "DJEN", court: court, medium: medium, criteria: criteria }
      end
    end
  end

  def insert_work(connection, run_id, work)
    connection.exec_params(<<~SQL, [run_id, JSON.generate(work)])
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
      SELECT $1::uuid, tenant_id, entity_type, entity_id, source, court, medium, criteria
      FROM jsonb_to_recordset($2::jsonb) AS job(
        tenant_id uuid, entity_type text, entity_id uuid, source text, court text, medium text, criteria jsonb)
    SQL
  end
end
