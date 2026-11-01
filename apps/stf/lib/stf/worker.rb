require "json"
require "pg"
require_relative "processor"

module STF
  class Worker
    def initialize(database_url:, processor: Processor.new(database_url: database_url), output: $stdout, errors: $stderr,
      sleeper: ->(seconds) { sleep(seconds) })
      @database_url, @processor, @output, @errors, @sleeper = database_url, processor, output, errors, sleeper
    end

    def run
      loop do
        begin
          @sleeper.call(5) unless run_once
        rescue LeaseLost
          @errors.puts "processing failed (lease lost)"
          @sleeper.call(5)
        end
      end
    end

    def run_once
      claim = PG.connect(@database_url) { |connection| Store.new(connection).next_job }
      return unless claim

      result = @processor.call_claimed(claim.fetch("job_id"), claim.fetch("token"), claim.fetch("state"))
      @output.puts JSON.generate(result)
      @output.flush
      result
    end
  end
end
