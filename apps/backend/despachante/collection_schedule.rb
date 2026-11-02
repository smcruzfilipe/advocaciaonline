require "date"
require "tzinfo"

class CollectionSchedule
  TIME_ZONE = TZInfo::Timezone.get("America/Sao_Paulo")
  TIME_FORMAT = /\A(?:[01][0-9]|2[0-3]):[0-5][0-9]\z/
  DEFAULT_WEEKDAYS = "1,2,3,4,5,6,7".freeze
  WEEKDAYS_FORMAT = /\A[1-7](?:,[1-7])*\z/

  def initialize(first:, second:, weekdays: DEFAULT_WEEKDAYS)
    @minutes = [minutes_for(first), minutes_for(second)]
    if @minutes.first < 4 * 60
      raise ArgumentError, "O primeiro horário da coleta não pode ser anterior a 04:00."
    end
    if @minutes.first >= @minutes.last
      raise ArgumentError, "Os horários da coleta devem ser distintos e ascendentes."
    end
    unless weekdays.is_a?(String) && WEEKDAYS_FORMAT.match?(weekdays)
      raise ArgumentError, "COLETA_DIAS_SEMANA deve conter dias ISO de 1 a 7 separados por vírgula."
    end
    @weekdays = weekdays.split(",").map(&:to_i)
    if @weekdays.uniq.length != @weekdays.length
      raise ArgumentError, "COLETA_DIAS_SEMANA não pode conter dias repetidos."
    end
  end

  def due(now:)
    date = TIME_ZONE.to_local(now).to_date
    return [] unless @weekdays.include?(date.cwday)

    slots_on(date).select { |slot| slot.fetch(:scheduled_at) <= now }
  end

  def next_at(now:)
    date = TIME_ZONE.to_local(now).to_date
    if @weekdays.include?(date.cwday)
      following = slots_on(date).find { |slot| slot.fetch(:scheduled_at) > now }
      return following.fetch(:scheduled_at) if following
    end

    begin
      date += 1
    end until @weekdays.include?(date.cwday)
    slots_on(date).first.fetch(:scheduled_at)
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
