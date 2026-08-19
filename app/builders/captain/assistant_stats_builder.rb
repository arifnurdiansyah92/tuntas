# Legacy metrics computed from assistant messages and reporting events. The
# outcome-episode based builders (overview/flow/trend) supersede these for V2.
class Captain::AssistantStatsBuilder
  include Captain::StatsTimeRange

  SECONDS_SAVED_PER_REPLY = 4.minutes.to_i

  def metrics
    current = window_stats(current_window)
    previous = window_stats(previous_window)

    %i[conversations_handled auto_resolution_rate handoff_rate hours_saved reopen_rate conversation_depth].index_with do |metric|
      {
        current: current[metric],
        previous: previous[metric],
        trend: trend_between(current[metric], previous[metric])
      }
    end
  end

  def faq_stats
    approved = assistant.responses.approved.count
    suggestions = assistant.faq_suggestions.open.count
    total = approved + suggestions

    {
      approved: approved,
      suggestions: suggestions,
      documents: assistant.documents.count,
      coverage: total.zero? ? 0 : ((approved / total.to_f) * 100).round
    }
  end

  private

  def window_stats(window)
    handled_ids = handled_conversation_ids(window)
    replies = reply_count(window)

    {
      conversations_handled: handled_ids.size,
      auto_resolution_rate: percentage_of(auto_resolved_ids(handled_ids, window).size, handled_ids.size),
      handoff_rate: percentage_of(handed_off_ids(handled_ids, window).size, handled_ids.size),
      hours_saved: ((replies * SECONDS_SAVED_PER_REPLY) / 3600.0).round,
      reopen_rate: reopen_rate(handled_ids, window),
      conversation_depth: handled_ids.empty? ? 0.0 : (replies / handled_ids.size.to_f).round(1)
    }
  end

  def handled_conversation_ids(window)
    assistant_messages(window).reorder(nil).distinct.pluck(:conversation_id)
  end

  def reply_count(window)
    assistant_messages(window).count
  end

  def assistant_messages(window)
    Message.where(
      account_id: assistant.account_id,
      sender: assistant,
      message_type: :outgoing,
      private: false,
      created_at: window
    )
  end

  def auto_resolved_ids(handled_ids, window)
    inference_resolved = event_conversation_ids(handled_ids, window, 'conversation_captain_inference_resolved')
    bot_resolved = event_conversation_ids(handled_ids, window, 'conversation_bot_resolved')

    inference_resolved | (bot_resolved - handed_off_ids(handled_ids, window))
  end

  def handed_off_ids(handled_ids, window)
    event_conversation_ids(handled_ids, window, %w[conversation_bot_handoff conversation_captain_inference_handoff])
  end

  def event_conversation_ids(handled_ids, window, names)
    return [] if handled_ids.empty?

    reporting_events(handled_ids, window, names).distinct.pluck(:conversation_id)
  end

  def reporting_events(handled_ids, window, names)
    ReportingEvent.where(account_id: assistant.account_id, conversation_id: handled_ids, name: names, created_at: window)
  end

  # A conversation counts as reopened when a conversation_opened event lands
  # after the captain resolve, using the reopen's actual time (event_end_time)
  # and only inside the reporting window.
  def reopen_rate(handled_ids, window)
    resolve_times = captain_resolve_times(handled_ids, window)
    return 0.0 if resolve_times.empty?

    reopened = ReportingEvent.where(
      account_id: assistant.account_id,
      conversation_id: resolve_times.keys,
      name: 'conversation_opened'
    ).where(event_end_time: ..window.end).pluck(:conversation_id, :event_end_time).count do |conversation_id, reopened_at|
      reopened_at.present? && reopened_at > resolve_times[conversation_id]
    end

    percentage_of(reopened, resolve_times.size)
  end

  def captain_resolve_times(handled_ids, window)
    return {} if handled_ids.empty?

    reporting_events(handled_ids, window, %w[conversation_bot_resolved conversation_captain_inference_resolved])
      .pluck(:conversation_id, :event_end_time)
      .each_with_object({}) do |(conversation_id, resolved_at), memo|
        next if resolved_at.blank?

        memo[conversation_id] = [memo[conversation_id], resolved_at].compact.min
      end
  end
end
