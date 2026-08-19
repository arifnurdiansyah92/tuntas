# Weekly/daily demand buckets of Captain-handled and Captain-resolved outcomes.
class Captain::AssistantResolutionTrendStatsBuilder
  include Captain::StatsTimeRange

  DAY_GRANULARITY_LIMIT = 15

  def metrics
    rows = outcome_rows

    { granularity: granularity, buckets: buckets(rows) }
  end

  private

  def granularity
    window_days > DAY_GRANULARITY_LIMIT ? :week : :day
  end

  def window_days
    (period[:ends_on] - period[:starts_on]).to_i + 1
  end

  def buckets(rows)
    bucket_bounds.map do |starts_on, ends_on|
      bucket_rows = rows.select { |row| row[:demand_on].between?(starts_on, ends_on) }
      {
        starts_on: starts_on,
        ends_on: ends_on,
        conversations_handled: bucket_rows.count { |row| row[:involved] },
        resolved_by_captain: bucket_rows.count { |row| row[:resolved_by_captain] }
      }
    end
  end

  def bucket_bounds
    if granularity == :week
      period[:starts_on].step(period[:ends_on], 7).map do |starts_on|
        [starts_on, [starts_on + 6.days, period[:ends_on]].min]
      end
    else
      (period[:starts_on]..period[:ends_on]).map { |date| [date, date] }
    end
  end

  def outcome_rows
    ConversationOutcome.where(assistant_id: assistant.id, started_at: current_window)
                       .pluck(:started_at, :first_captain_reply_at, :handoff_at, :handoff_reason_category, :first_human_reply_at, :resolved_at)
                       .filter_map do |started_at, first_captain_reply_at, handoff_at, category, first_human_reply_at, resolved_at|
      involved = first_captain_reply_at.present? || (handoff_at.present? && category != 'usage_limit')
      next unless involved

      {
        demand_on: started_at.in_time_zone(zone).to_date,
        involved: true,
        resolved_by_captain: resolved_at.present? && handoff_at.blank? && first_human_reply_at.blank?
      }
    end
  end
end
