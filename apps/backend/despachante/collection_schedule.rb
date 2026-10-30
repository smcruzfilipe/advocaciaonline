require "date"
require "tzinfo"

class CollectionSchedule
  TIME_ZONE = TZInfo::Timezone.get("America/Sao_Paulo")
  TIME_FORMAT = /\A(?:[01][0-9]|2[0-3]):[0-5][0-9]\z/

  def initialize(first:, second:)
    @minutes = [minutes_for(first), minutes_for(second)]
    if @minutes.first < 4 * 60
      raise ArgumentError, "O primeiro horário da coleta não pode ser anterior a 04:00."
    end
    if @minutes.first >= @minutes.last
      raise ArgumentError, "Os horários da coleta devem ser distintos e ascendentes."
    end
  end

  def due(now:)
    date = TIME_ZONE.to_local(now).to_date
    slots_on(date).select { |slot| slot.fetch(:scheduled_at) <= now }
  end

  def next_at(now:)
    date = TIME_ZONE.to_local(now).to_date
    following = slots_on(date).find { |slot| slot.fetch(:scheduled_at) > now }
    return following.fetch(:scheduled_at) if following

    slots_on(date + 1).first.fetch(:scheduled_at)
  end

  private

  def slots_on(date)
    @minutes.each_with_index.map do |minutes, index|
      hour, minute = minutes.divmod(60)
      scheduled_at = TIME_ZONE.local_time(date.year, date.month, date.day, hour, minute).utc
      { slot: index + 1, date: date, scheduled_at: scheduled_at }
    end
  end

  def minutes_for(value)
    unless value.is_a?(String) && TIME_FORMAT.match?(value)
      raise ArgumentError, "Informe cada horário da coleta no formato estrito HH:MM de 24 horas."
    end

    value[0, 2].to_i * 60 + value[3, 2].to_i
  end
end
