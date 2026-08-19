# Overview metrics computed from Captain conversation-outcome episodes.
class Captain::AssistantOverviewStatsBuilder
  include Captain::StatsTimeRange

  SECONDS_SAVED_PER_REPLY = 4.minutes.to_i
  DURABILITY_WINDOW = 7.days
  METRIC_KEYS = %i[
    conversations_handled auto_resolution_rate autonomous_resolutions handoff_rate handoff_count
    hours_saved reopen_rate conversation_depth durable_resolution_rate
    autonomous_csat_score assisted_csat_score human_only_csat_score median_resolution_seconds
  ].freeze

  def metrics
    current = window_stats(current_window)
    previous = window_stats(previous_window)

    METRIC_KEYS.index_with do |metric|
      { current: current[metric], previous: previous[metric], trend: trend_between(current[metric], previous[metric]) }
    end
  end

  private

  def window_stats(window)
    episodes = episodes_in(window)
    involved = involved_episodes(episodes)
    autonomous = autonomous_resolutions(involved)
    handoffs = involved.count { |episode| episode.handoff_at.present? }
    replies_by_episode = reply_counts_by_episode(episodes, window)
    total_replies = replies_by_episode.values.sum

    funnel_stats(involved, autonomous, handoffs)
      .merge(activity_stats(replies_by_episode, total_replies))
      .merge(quality_stats(involved, autonomous, window))
  end

  def funnel_stats(involved, autonomous, handoffs)
    {
      conversations_handled: involved.size,
      autonomous_resolutions: autonomous.size,
      auto_resolution_rate: percentage_of(autonomous.size, involved.size),
      handoff_rate: percentage_of(handoffs, involved.size),
      handoff_count: handoffs,
      reopen_rate: percentage_of(autonomous.count { |episode| episode.ended_at.present? }, autonomous.size)
    }
  end

  def activity_stats(replies_by_episode, total_replies)
    active_episodes = replies_by_episode.values.count(&:positive?)

    {
      hours_saved: ((total_replies * seconds_saved_per_reply) / 3600.0).round,
      conversation_depth: active_episodes.zero? ? 0.0 : (total_replies / active_episodes.to_f).round(1)
    }
  end

  def quality_stats(involved, autonomous, window)
    assisted = involved.select { |episode| episode.resolved_at.present? && (episode.first_human_reply_at.present? || episode.handoff_at.present?) }

    {
      durable_resolution_rate: durable_resolution_rate(autonomous),
      autonomous_csat_score: average_rating(autonomous),
      assisted_csat_score: average_rating(assisted),
      human_only_csat_score: human_only_csat_score(window),
      median_resolution_seconds: median_resolution_seconds(involved)
    }
  end

  def episodes_in(window)
    ConversationOutcome.where(assistant_id: assistant.id, started_at: window).to_a
  end

  # Captain was involved when it replied, or when it recorded a handoff for any
  # reason other than exhausting the usage quota before engaging.
  def involved_episodes(episodes)
    episodes.select do |episode|
      episode.first_captain_reply_at.present? ||
        (episode.handoff_at.present? && episode.handoff_reason_category != 'usage_limit')
    end
  end

  def autonomous_resolutions(involved)
    involved.select do |episode|
      episode.resolved_at.present? && episode.first_captain_reply_at.present? &&
        episode.handoff_at.blank? && episode.first_human_reply_at.blank?
    end
  end

  # Only resolutions old enough to observe are judged; a resolution is durable
  # when the episode was not reopened within the observation window.
  def durable_resolution_rate(autonomous)
    observable = autonomous.select { |episode| episode.resolved_at <= DURABILITY_WINDOW.ago }
    durable = observable.count do |episode|
      episode.ended_at.blank? || episode.ended_at > episode.resolved_at + DURABILITY_WINDOW
    end

    percentage_of(durable, observable.size)
  end

  def average_rating(episodes)
    ratings = episodes.filter_map(&:csat_rating)
    return 0 if ratings.empty?

    (ratings.sum / ratings.size.to_f).round(1)
  end

  def human_only_csat_score(window)
    ratings = CsatSurveyResponse.where(account_id: assistant.account_id, created_at: window)
                                .where.not(conversation_id: ConversationOutcome.where(account_id: assistant.account_id).select(:conversation_id))
                                .pluck(:rating)
    return 0 if ratings.empty?

    (ratings.sum / ratings.size.to_f).round(1)
  end

  def median_resolution_seconds(involved)
    durations = involved.filter_map { |episode| (episode.resolved_at - episode.started_at).to_i if episode.resolved_at.present? }.sort
    return 0 if durations.empty?

    middle = durations.size / 2
    (durations.size.odd? ? durations[middle] : (durations[middle - 1] + durations[middle]) / 2.0).round
  end

  def reply_counts_by_episode(episodes, window)
    return {} if episodes.empty?

    message_times = Message.where(
      account_id: assistant.account_id,
      sender: assistant,
      message_type: :outgoing,
      private: false,
      conversation_id: episodes.map(&:conversation_id).uniq,
      created_at: window
    ).pluck(:conversation_id, :created_at).group_by(&:first)

    episodes.index_with do |episode|
      times = message_times[episode.conversation_id] || []
      times.count { |_conversation_id, created_at| within_episode?(episode, created_at) }
    end
  end

  def within_episode?(episode, time)
    time >= episode.started_at && (episode.ended_at.blank? || time <= episode.ended_at)
  end

  def seconds_saved_per_reply
    self.class::SECONDS_SAVED_PER_REPLY
  end
end
