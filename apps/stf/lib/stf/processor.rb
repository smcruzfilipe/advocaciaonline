require "date"
require "pg"
require "time"
require "tzinfo"
require_relative "errors"
require_relative "store"
require_relative "http"
require_relative "discovery"
require_relative "process_lookup"
require_relative "andamentos"

module STF
  class Processor
    TIMEZONE = TZInfo::Timezone.get("America/Sao_Paulo")

    def initialize(database_url:, http_factory: ->(callback) { Http.new(before_request: callback) },
      date_source: -> { TIMEZONE.now.to_date }, time_source: -> { Time.now })
      @database_url = database_url
      @http_factory = http_factory
      @date_source = date_source
      @time_source = time_source
    end

    def call(job_id)
      PG.connect(@database_url) do |connection|
        store = Store.new(connection)
        claim = store.claim(job_id)
        process_claimed(store, job_id, claim.fetch("token"), claim.fetch("state"))
      end
    rescue PG::InvalidAuthorizationSpecification
      raise LeaseLost, "processor lease unavailable", cause: nil
    end

    def call_claimed(job_id, token, state)
      PG.connect(@database_url) { |connection| process_claimed(Store.new(connection), job_id, token, state) }
    rescue PG::InvalidAuthorizationSpecification
      raise LeaseLost, "processor lease unavailable", cause: nil
    end

    private

    def process_claimed(store, job_id, token, state)
      return store.commit(job_id, token, []) if state == "succeeded"
      return { "state" => state } if state == "failed"

      job = store.job(job_id, token)
      date = Date.iso8601(job.fetch("collection_date"))
      begin
        guard = -> {
          raise Interrupted unless @date_source.call == date
          store.renew(job_id, token)
          raise Interrupted unless @date_source.call == date
        }
        guard.call
        store.start(job_id, token)
        http = @http_factory.call(guard)
        discovery = Discovery.new(http: http)
        criteria = job.fetch("criteria")
        processes = case job.fetch("entity_type")
        when "lawyer" then discovery.search(name: criteria.fetch("name"), type: "ADVOGADO")
        when "party" then discovery.search(name: criteria.fetch("name"), type: "PARTE")
        when "process" then [ProcessLookup.new(http: http, discovery: discovery).resolve(criteria)].compact
        else raise InvalidSource, "unsupported entity type"
        end
        andamentos = Andamentos.new(http: http)
        payload = processes.map do |process|
          process.merge("em_tramitacao" => "Sim",
            "items" => andamentos.fetch(process: process, date: date, captured_at: @time_source.call.utc))
        end
        guard.call
        store.commit(job_id, token, payload)
      rescue Interrupted
        store.fail(job_id, token, "interrupted")
      rescue SourceUnavailable
        store.fail(job_id, token, @date_source.call == date ? "source_unavailable" : "interrupted")
      rescue InvalidSource
        store.fail(job_id, token, @date_source.call == date ? "invalid_source" : "interrupted")
      rescue PG::InvalidAuthorizationSpecification
        return store.fail(job_id, token, "interrupted") unless @date_source.call == date
        raise
      rescue PG::ConnectionBad, PG::UnableToSend
        raise
      rescue StandardError
        store.fail(job_id, token, @date_source.call == date ? "processing_failed" : "interrupted")
      end
    end
  end
end
