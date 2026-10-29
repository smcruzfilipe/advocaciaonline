require "date"
require "json"
require "pg"
require "time"
require "tzinfo"
require_relative "errors"
require_relative "http"
require_relative "caderno"
require_relative "fallback"
require_relative "matcher"
require_relative "sanitizer"

module Processador
  # Each invocation handles one frozen job, either explicitly claimed here or
  # atomically selected by the worker. Callers cannot supply a tenant.
  class Runner
    API_BASE = "https://comunicaapi.pje.jus.br/api/v1".freeze
    TIMEZONE = TZInfo::Timezone.get("America/Sao_Paulo")
    # Any longer delay crosses the current local day, where work is interrupted.
    MAX_WAIT_FOR_CURRENT_DAY = 172_800
    DateChanged = Class.new(StandardError)
    LeaseLost = Class.new(StandardError)

    def initialize(database_url:, http: Http.new, base_url: API_BASE, attempts: 3, backoff_first: 60, backoff_second: 300, date_source: -> { TIMEZONE.now.to_date })
      raise ArgumentError, "invalid attempts" unless (1..3).cover?(attempts)
      raise ArgumentError, "invalid backoff" unless backoff_first.positive? && backoff_second.positive?

      @database_url = database_url
      @http = http
      @attempts = attempts
      @backoff_first = backoff_first
      @backoff_second = backoff_second
      @date_source = date_source
      @sources = {
        "caderno" => Caderno.new(http: http, base_url: base_url),
        "fallback" => Fallback.new(http: http, base_url: base_url)
      }
    end

    def call(job_id)
      PG.connect(@database_url) do |db|
        claim = db.exec_params("SELECT * FROM app_private.processor_claim_available($1::uuid)", [job_id]).first
        process_claimed(db, job_id, claim.fetch("token"), claim.fetch("state"))
      end
    end

    def call_claimed(job_id, token, state)
      PG.connect(@database_url) do |db|
        process_claimed(db, job_id, token, state, defer_retry: true)
      end
    ensure
      @http.reset_retry_wait
    end

    private

    def process_claimed(db, job_id, token, state, defer_retry: false)
      return { "state" => state } if %w[succeeded failed].include?(state)

      job = json_call(db, "processor_job", "$1::uuid, $2::text", [job_id, token])
      return record_failure(db, job_id, token, "interrupted") unless current_date?(job)

      db.exec_params("SELECT * FROM app_private.processor_start($1::uuid, $2::text)", [job_id, token])
      previous_callback = @http.on_retry_after
      @http.on_retry_after = ->(seconds) {
        db.exec_params("SELECT app_private.processor_defer($1::uuid, $2::text, $3::integer)", [job_id, token, [seconds, MAX_WAIT_FOR_CURRENT_DAY].min])
      }
      begin
        with_lease(job_id, token) { |lease| execute(db, job_id, token, job, lease, defer_retry: defer_retry) }
      ensure
        @http.on_retry_after = previous_callback
      end
    rescue PG::InvalidAuthorizationSpecification
      # The selector and processor use separate connections. Expiry or a newer
      # owner must stop this invocation, never write a failure for that owner.
      raise LeaseLost, "Processor operation unavailable", cause: nil
    end

    def execute(db, job_id, token, job, lease, defer_retry:)
      progress = job
      if progress.fetch("attempt_in_flight")
        progress = fail_attempt(db, job_id, token, 0)
      end

      loop do
        lease.check!
        return record_failure(db, job_id, token, "interrupted") unless current_date?(job)
        exhausted = progress["exhausted"] ||
          (progress["phase"] == "fallback" && progress["fallback_attempts"] >= @attempts && !progress["attempt_in_flight"])
        return record_failure(db, job_id, token, "source_unavailable") if exhausted

        if progress["next_attempt_at"]
          remaining = Time.parse(progress.fetch("next_attempt_at")) - Time.now
          if remaining.positive?
            if defer_retry
              db.exec_params("SELECT app_private.processor_release($1::uuid, $2::text)", [job_id, token])
              return { "state" => "deferred" }
            end
            sleep([remaining, 60].min)
            next
          end
        end

        progress = json_call(db, "processor_attempt_begin", "$1::uuid, $2::text, $3::integer", [job_id, token, @attempts])
        next if progress["deferred"]
        source_path = progress.fetch("phase")
        matches = []
        begin
          before_request = -> {
            loop do
              lease.check!
              raise DateChanged unless current_date?(job)
              remaining = @http.retry_wait_remaining
              break unless remaining.positive?
              sleep([remaining, 60].min)
            end
          }
          @sources.fetch(source_path).each(court: job.fetch("court"), date: Date.iso8601(job.fetch("collection_date")),
            medium: job.fetch("medium"), before_request: before_request) do |publication|
            lease.check!
            if Matcher.match?(entity_type: job.fetch("entity_type"), criteria: job.fetch("criteria"), publication: publication)
              matches << (source_path == "fallback" ? Sanitizer.publication(publication) : publication)
            end
          end
          lease.check!
          return record_failure(db, job_id, token, "interrupted") unless current_date?(job)
          return json_call(db, "processor_commit", "$1::uuid, $2::text, $3::text, $4::jsonb", [job_id, token, source_path, JSON.generate(matches)])
        rescue DateChanged
          return record_failure(db, job_id, token, "interrupted")
        rescue SourceError => error
          progress = fail_attempt(db, job_id, token, error.retry_after || 0)
        rescue PG::Error => error
          raise if fatal_database_error?(error)
          return record_failure(db, job_id, token, current_date?(job) ? "processing_failed" : "interrupted")
        rescue StandardError
          return record_failure(db, job_id, token, current_date?(job) ? "processing_failed" : "interrupted")
        end
      end
    end

    def fatal_database_error?(error)
      return true if error.is_a?(PG::ConnectionBad) || error.is_a?(PG::UnableToSend)

      state = error.result&.error_field(PG::Result::PG_DIAG_SQLSTATE)
      # Broken connections, authorization, missing schema/functions, resource
      # exhaustion and invalid configuration require operator intervention.
      state.nil? || %w[08 28 3D 3F 42 53 54 57 58 XX].include?(state[0, 2]) || state == "22023"
    end

    def current_date?(job)
      Date.iso8601(job.fetch("collection_date")) == @date_source.call
    end

    def fail_attempt(db, job_id, token, retry_after)
      json_call(db, "processor_attempt_failed", "$1::uuid, $2::text, $3::integer, $4::integer, $5::integer, $6::integer",
        [job_id, token, [retry_after.ceil, MAX_WAIT_FOR_CURRENT_DAY].min, @attempts, @backoff_first, @backoff_second])
    end

    def record_failure(db, job_id, token, code)
      json_call(db, "processor_record_failure", "$1::uuid, $2::text, $3::text", [job_id, token, code])
    end

    def json_call(db, function, arguments, params)
      result = db.exec_params("SELECT app_private.#{function}(#{arguments})::text AS result", params).first
      JSON.parse(result.fetch("result"))
    end

    # The download can outlive a lease; renew on a separate connection while
    # the main connection is blocked in HTTP or processing the ZIP.
    def with_lease(job_id, token)
      lease = Lease.new(@database_url, job_id, token)
      yield lease
    ensure
      lease&.close
    end

    class Lease
      def initialize(database_url, job_id, token)
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @closed = false
        @error = nil
        @thread = Thread.new do
          PG.connect(database_url) do |db|
            loop do
              stop = @mutex.synchronize do
                @condition.wait(@mutex, 60) unless @closed
                @closed
              end
              break if stop
              db.exec_params("SELECT * FROM app_private.processor_renew($1::uuid, $2::text)", [job_id, token])
            end
          end
        rescue StandardError => error
          @mutex.synchronize { @error = error }
        end
      end

      def check!
        error = @mutex.synchronize { @error }
        raise error if error
      end

      def close
        @mutex.synchronize do
          @closed = true
          @condition.signal
        end
        @thread.join
      end
    end
  end
end
