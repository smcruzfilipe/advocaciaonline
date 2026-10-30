require "json"

# The caller holds DatabaseContext.with_session and authorize_session!'s lock.
class CommunicationQuery
  UUID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

  def initialize(context:, groups:)
    @tenant_id = context.fetch("tenant_id")
    @owner = context.fetch("role") == "owner"
    @groups = groups
    @connection = ApplicationRecord.connection
  end

  def list
    records.group_by { |record| record.fetch("court") }.map do |court, communications|
      { court: court, communications: communications.map { |record| serialize(record) } }
    end
  end

  def find(id)
    return unless id.is_a?(String) && UUID.match?(id)

    record = records(id: id).first
    return unless record

    serialize(record).merge(payload: JSON.parse(record.fetch("payload")), links: links(record))
  end

  private

  def permitted_courts
    @connection.exec_query(<<~SQL, "Communication tribunals", binds(@tenant_id)).filter_map do |row|
      SELECT court FROM public.collection_jobs WHERE tenant_id = $1::uuid
      UNION
      SELECT payload->>'siglaTribunal' AS court FROM public.collection_communications
      WHERE tenant_id = $1::uuid AND jsonb_typeof(payload->'siglaTribunal') = 'string'
      ORDER BY court
    SQL
      court = row.fetch("court")
      court if AuthorizationPolicy.allowed?(owner: @owner, groups: @groups,
        operation: "consultar_comunicacoes", court: court)
    end
  end

  def records(id: nil)
    courts = permitted_courts
    return [] if courts.empty?

    # Deduplication preserves the first payload, not the latest encounter. Find
    # its tribunal BEFORE filtering permission; a later allowed link is no grant
    # to that first payload. Conflicting earliest tribunals are not attributable.
    # https://www.postgresql.org/docs/18/queries-table-expressions.html
    @connection.exec_query(<<~SQL, "Authorized communications", binds(@tenant_id, JSON.generate(courts), id)).to_a
      WITH first_link_times AS (
        SELECT tenant_id, communication_id, min(recorded_at) AS recorded_at
        FROM public.collection_communication_links
        WHERE tenant_id = $1::uuid AND ($3::uuid IS NULL OR communication_id = $3::uuid)
        GROUP BY tenant_id, communication_id
      ), origins AS (
        SELECT first.tenant_id, first.communication_id, min(job.court) AS court
        FROM first_link_times AS first
        JOIN public.collection_communication_links AS link
          ON link.tenant_id = first.tenant_id AND link.communication_id = first.communication_id
          AND link.recorded_at = first.recorded_at
        JOIN public.collection_jobs AS job ON job.tenant_id = link.tenant_id AND job.id = link.job_id
        GROUP BY first.tenant_id, first.communication_id
        HAVING count(DISTINCT job.court) = 1
      )
      SELECT communication.id, communication.source, communication.identity_status, communication.warning,
        origin.court, communication.payload->>'numero_processo' AS process_number,
        jsonb_typeof(communication.payload->'numero_processo') = 'string' AS process_number_supplied
        #{id ? ', communication.payload::text AS payload' : ''}
      FROM public.collection_communications AS communication
      JOIN origins AS origin ON origin.tenant_id = communication.tenant_id AND origin.communication_id = communication.id
      WHERE communication.tenant_id = $1::uuid AND ($3::uuid IS NULL OR communication.id = $3::uuid)
        AND origin.court IN (SELECT jsonb_array_elements_text($2::jsonb))
        AND (jsonb_typeof(communication.payload->'siglaTribunal') IS DISTINCT FROM 'string'
          OR communication.payload->>'siglaTribunal' !~ '^[A-Za-z][A-Za-z0-9]{1,31}$'
          OR communication.payload->>'siglaTribunal' = origin.court
          OR communication.payload->>'siglaTribunal' IN (SELECT jsonb_array_elements_text($2::jsonb)))
      ORDER BY origin.court, communication.recorded_at, communication.id
    SQL
  end

  def links(record)
    # A later encounter never authorizes the first payload. Once the origin is
    # authorized, return only links in tribunals the identity may also read.
    @connection.exec_query(<<~SQL, "Communication monitoring links", binds(@tenant_id, record.fetch("id"), JSON.generate(permitted_courts))).to_a
      SELECT job.id AS job_id, job.run_id, job.entity_type, job.entity_id, job.court, job.medium
      FROM public.collection_communication_links AS link
      JOIN public.collection_jobs AS job ON job.tenant_id = link.tenant_id AND job.id = link.job_id
      WHERE link.tenant_id = $1::uuid AND link.communication_id = $2::uuid
        AND job.court IN (SELECT jsonb_array_elements_text($3::jsonb))
      ORDER BY link.recorded_at, job.id
    SQL
  end

  def serialize(record)
    result = record.slice("id", "court", "source", "identity_status", "warning")
    result["process_number"] = record.fetch("process_number") if record.fetch("process_number_supplied") == true
    result
  end

  def binds(*values)
    values.each_with_index.map do |value, index|
      ActiveRecord::Relation::QueryAttribute.new("argument_#{index}", value, ActiveRecord::Type::String.new)
    end
  end
end
