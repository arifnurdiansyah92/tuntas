# Sankey-style resolution flow for Captain-involved conversation outcomes.
class Captain::AssistantResolutionFlowBuilder
  include Captain::StatsTimeRange

  REOPEN_WINDOW = 7.days
  TOP_REASON_NODES = 2

  def build
    involved = involved_episodes
    resolved = resolved_by_captain(involved)
    handoffs = involved.select { |episode| episode.handoff_at.present? }
    reason_counts = handoff_reason_counts(handoffs)
    stats = {
      handled: involved.size,
      resolved: resolved.size,
      handoffs: handoffs.size,
      closed_with_team: involved.count do |episode|
        episode.resolved_at.present? && episode.handoff_at.blank? && episode.first_human_reply_at.present?
      end,
      reopened: resolved.count { |episode| reopened_quickly?(episode) }
    }

    {
      sankey: sankey(stats, reason_counts),
      handoff_distribution: handoff_distribution(reason_counts, handoffs.size)
    }
  end

  private

  def sankey(stats, reason_counts)
    reason_nodes = reason_flow_counts(reason_counts)

    {
      nodes: [
        { id: :conversations_handled, count: stats[:handled] },
        { id: :resolved_by_captain, count: stats[:resolved] },
        { id: :handed_off, count: stats[:handoffs] },
        { id: :closed_with_team, count: stats[:closed_with_team] },
        { id: :reopened_within_7_days, count: stats[:reopened] },
        { id: :stayed_closed, count: stats[:resolved] - stats[:reopened] }
      ] + reason_nodes.map { |id, count| { id: id, count: count } },
      links: [
        { source: :conversations_handled, target: :resolved_by_captain, value: stats[:resolved] },
        { source: :conversations_handled, target: :handed_off, value: stats[:handoffs] },
        { source: :conversations_handled, target: :closed_with_team, value: stats[:closed_with_team] },
        { source: :resolved_by_captain, target: :reopened_within_7_days, value: stats[:reopened] },
        { source: :resolved_by_captain, target: :stayed_closed, value: stats[:resolved] - stats[:reopened] }
      ] + reason_nodes.map { |id, count| { source: :handed_off, target: id, value: count } }
    }
  end

  # The top classified reasons become dedicated nodes; the remaining classified
  # reasons and unclassified handoffs are grouped under :other_reasons.
  def reason_flow_counts(reason_counts)
    classified = reason_counts.except('unclassified').sort_by { |category, count| [-count, category] }
    top = classified.first(TOP_REASON_NODES)
    other = (classified.drop(TOP_REASON_NODES).sum { |_category, count| count }) + reason_counts.fetch('unclassified', 0)

    nodes = top.map { |category, count| [:"handoff_reason_#{category}", count] }
    nodes << [:other_reasons, other] if other.positive?
    nodes
  end

  def handoff_distribution(reason_counts, total)
    reason_counts.sort_by { |category, count| [-count, category] }.map do |category, count|
      { category: category, count: count, percentage: percentage_of(count, total) }
    end
  end

  def handoff_reason_counts(handoffs)
    handoffs.group_by { |episode| episode.handoff_reason_category.presence || 'unclassified' }
            .transform_values(&:size)
  end

  def involved_episodes
    ConversationOutcome.where(assistant_id: assistant.id, started_at: current_window).to_a.select do |episode|
      episode.first_captain_reply_at.present? ||
        (episode.handoff_at.present? && episode.handoff_reason_category != 'usage_limit')
    end
  end

  def resolved_by_captain(involved)
    involved.select do |episode|
      episode.resolved_at.present? && episode.handoff_at.blank? && episode.first_human_reply_at.blank?
    end
  end

  def reopened_quickly?(episode)
    episode.ended_at.present? && episode.resolved_at.present? && (episode.ended_at - episode.resolved_at) < REOPEN_WINDOW
  end
end
