class Sla::BusinessHoursService
  pattr_initialize [:inbox!, :start_time!, :threshold_seconds!, :working_hours_by_day]

  MAX_LOOKAHEAD_DAYS = 366

  def deadline
    return start_time + threshold_seconds unless business_hours_applicable?

    business_deadline
  end

  private

  def working_hours_index
    @working_hours_index ||= working_hours_by_day || inbox.working_hours.index_by(&:day_of_week)
  end

  def business_hours_applicable?
    return false unless inbox.working_hours_enabled?

    working_hours_index.values.any? { |working_hour| !working_hour.closed_all_day? }
  end

  def business_deadline
    remaining = threshold_seconds.to_f
    current = start_time.in_time_zone(timezone)

    MAX_LOOKAHEAD_DAYS.times do
      deadline, current, remaining = consume_day(current, remaining)
      return deadline if deadline
    end

    start_time + threshold_seconds
  end

  def timezone
    ActiveSupport::TimeZone[inbox.timezone] || Time.zone
  end

  # Consumes as much of `remaining` as fits in the current day's business window.
  # Returns [deadline, current, remaining]; deadline is nil while more days are needed.
  def consume_day(current, remaining)
    working_hour = working_hours_index[current.wday]
    return [nil, next_day_start(current), remaining] if working_hour.nil? || working_hour.closed_all_day?

    close_time = day_close(current, working_hour)
    current = [current, day_open(current, working_hour)].max
    return [nil, next_day_start(current), remaining] if current >= close_time

    available = close_time - current
    return [current + remaining, current, remaining] if remaining <= available

    [nil, next_day_start(current), remaining - available]
  end

  def day_open(day, working_hour)
    return day.beginning_of_day if working_hour.open_all_day?

    day.change(hour: working_hour.open_hour, min: working_hour.open_minutes)
  end

  def day_close(day, working_hour)
    return day.beginning_of_day + 24.hours if working_hour.open_all_day?

    day.change(hour: working_hour.close_hour, min: working_hour.close_minutes)
  end

  def next_day_start(current)
    (current + 1.day).beginning_of_day
  end
end
