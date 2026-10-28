ENV["BUNDLE_GEMFILE"] ||= File.expand_path("Gemfile", __dir__)
require "bundler/setup"
require_relative "collection_schedule"
require_relative "collection_planner"

class PlannerRunner
  RECONCILE_INTERVAL = 60
  CATALOG_RETRY_SECONDS = 60

  def initialize(planner_url:, first:, second:)
    @schedule = CollectionSchedule.new(first: first, second: second)
    unless planner_url.is_a?(String) && !planner_url.strip.empty?
      raise ArgumentError, "PLANNER_DATABASE_URL é obrigatória para o processo de planejamento."
    end
    @planner = CollectionPlanner.new(url: planner_url)
  end

  def run_once(now:)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    clock = -> { now + (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) }
    @planner.interrupt_before(now: clock.call)
    catalog = round_catalog
    failure = nil
    ids = []
    begin
      @schedule.due(now: now).each do |due_slot|
        current = clock.call
        break unless @schedule.due(now: current).include?(due_slot)

        begin
          ids << @planner.plan(slot: due_slot.fetch(:slot), now: current, catalog: catalog)
        rescue CourtCatalog::Unavailable => error
          failure ||= error
        end
      end
    ensure
      @planner.interrupt_before(now: clock.call)
    end
    raise failure if failure

    ids
  end

  def next_wait(reconciled_at:, now:)
    return 0 if @schedule.due(now: now) != @schedule.due(now: reconciled_at)

    waits = [RECONCILE_INTERVAL, @schedule.next_at(now: now) - now]
    if @catalog_retry_at
      remaining = @catalog_retry_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      waits << remaining if remaining > 0
    end
    waits.min
  end

  private

  def round_catalog
    resolved = false
    result = nil
    failure = nil
    # The planner invokes this only for unfinished slots; finalized plans need no source access.
    lambda do
      unless resolved
        resolved = true
        begin
          result = fetch_catalog
        rescue StandardError => error
          failure = error
        end
      end
      raise failure if failure

      result
    end
  end

  def fetch_catalog
    if @catalog_error && Process.clock_gettime(Process::CLOCK_MONOTONIC) < @catalog_retry_at
      raise @catalog_error
    end

    begin
      result = CourtCatalog.fetch
    rescue CourtCatalog::Unavailable => error
      @catalog_error = error
      # The minimum interval starts AFTER the failed response, not before the request.
      @catalog_retry_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + CATALOG_RETRY_SECONDS
      raise
    end
    @catalog_error = @catalog_retry_at = nil
    result
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    runner = PlannerRunner.new(planner_url: ENV.fetch("PLANNER_DATABASE_URL"),
      first: ENV.fetch("COLETA_HORARIO_1"), second: ENV.fetch("COLETA_HORARIO_2"))

    loop do
      reconciled_at = Time.now
      begin
        runner.run_once(now: reconciled_at)
      rescue CourtCatalog::Unavailable => error
        warn "Falha de catálogo no planejamento: #{error.class}."
      end
      sleep runner.next_wait(reconciled_at: reconciled_at, now: Time.now)
    end
  rescue StandardError, SecurityError => error
    warn "Planejador encerrado: #{error.class}."
    exit 1
  end
end
