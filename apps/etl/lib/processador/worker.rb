require "json"
require "pg"
require_relative "runner"

module Processador
  class Worker
    def initialize(database_url:, runner: Runner.new(database_url: database_url), output: $stdout, errors: $stderr,
      idle_wait: 5, sleeper: ->(seconds) { sleep(seconds) })
      unless idle_wait.is_a?(Numeric) && idle_wait.real? && idle_wait.finite? && idle_wait.positive? && idle_wait <= 60
        raise ArgumentError, "idle wait must be positive finite seconds, at most 60"
      end

      @database_url = database_url
      @runner = runner
      @output = output
      @errors = errors
      @idle_wait = idle_wait
      @sleeper = sleeper
    end

    def run
      loop do
        @sleeper.call(@idle_wait) unless run_once
      end
    end

    # A round owns just one short-lived selection connection. Processing and
    # renewal never hold its transaction open or acquire a second claim.
    # Returns nil when idle or when another owner has superseded the lease.
    def run_once
      claim = PG.connect(@database_url) do |db|
        db.exec_params("SELECT * FROM app_private.processor_next($1::integer)", [@runner.attempts]).first
      end
      return unless claim

      begin
        result = @runner.call_claimed(claim.fetch("job_id"), claim.fetch("token"), claim.fetch("state"))
      rescue Runner::LeaseLost => error
        @errors.puts "processing failed (#{error.class})"
        return
      end
      @output.puts JSON.generate(result)
      @output.flush
      result
    end
  end
end
