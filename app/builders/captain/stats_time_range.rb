# Shared reporting window handling for Captain stats builders: validated range
# keys, viewer-timezone anchored period bounds, and the current/previous windows.
module Captain::StatsTimeRange
  ALLOWED_RANGES = %w[7 30 90 this_month last_month].freeze
  DEFAULT_RANGE = '7'.freeze

  attr_reader :assistant, :range

  def initialize(assistant, range = nil, timezone_offset = nil)
    @assistant = assistant
    @range = ALLOWED_RANGES.include?(range.to_s) ? range.to_s : DEFAULT_RANGE
    @timezone_offset = timezone_offset
  end

  def period
    @period ||=
      case range
      when 'this_month'
        { label: 'this month', starts_on: local_now.beginning_of_month.to_date, ends_on: local_now.to_date }
      when 'last_month'
        previous_month = local_now.last_month
        { label: 'last month', starts_on: previous_month.beginning_of_month.to_date, ends_on: previous_month.end_of_month.to_date }
      else
        { label: "the last #{range} days", starts_on: local_now.to_date - range.to_i.days, ends_on: local_now.to_date }
      end
  end

  private

  def zone
    @zone ||= begin
      offset = (@timezone_offset.presence || 0).to_f
      (offset.zero? ? nil : ActiveSupport::TimeZone[offset]) || ActiveSupport::TimeZone['UTC']
    end
  end

  def local_now
    Time.current.in_time_zone(zone)
  end

  def current_window
    @current_window ||= window_for(period[:starts_on], period[:ends_on])
  end

  def previous_window
    @previous_window ||=
      case range
      when 'this_month', 'last_month'
        previous_month = period[:starts_on].prev_month
        window_for(previous_month.beginning_of_month, previous_month.end_of_month)
      else
        window_for(period[:starts_on] - range.to_i.days, period[:starts_on] - 1.day)
      end
  end

  def window_for(starts_on, ends_on)
    starts_on.in_time_zone(zone)..ends_on.in_time_zone(zone).end_of_day
  end

  def trend_between(current, previous)
    return current if previous.zero?

    (((current - previous) / previous.to_f) * 100).round(1)
  end

  def percentage_of(numerator, denominator)
    return 0.0 if denominator.zero?

    ((numerator / denominator.to_f) * 100).round(1)
  end
end
