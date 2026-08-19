class Captain::ConversationOutcomeTracker
  def initialize(conversation:, assistant:)
    @conversation = conversation
    @assistant = assistant
  end

  def record_eligibility(at:)
    guarded do
      open_episode || create_episode(trigger: 'initial', at: at)
    end
  end

  def record_reopen(at:)
    guarded do
      next if episodes.none?

      open_episode&.update!(ended_at: at)
      create_episode(trigger: 'reopen', at: at)
    end
  end

  def record_handoff(at:, reason_category: nil)
    guarded do
      episode = episode_active_at(at)
      next if episode.blank?

      episode.update!(
        reply_snapshot(episode, at).merge(
          handoff_at: at,
          handoff_reason_category: normalized_reason_category(reason_category)
        )
      )
    end
  end

  def record_resolution(at:)
    guarded do
      episode = episode_active_at(at)
      next if episode.blank?

      episode.update!(reply_snapshot(episode, at).merge(resolved_at: at))
    end
  end

  def record_csat(response:)
    guarded do
      episode = episode_active_at(response.message.created_at)
      next if episode.blank?

      episode.update!(csat_rating: response.rating, csat_received_at: response.created_at)
    end
  end

  private

  def guarded
    yield
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: @conversation.account).capture_exception
    nil
  end

  def episodes
    ConversationOutcome.where(conversation_id: @conversation.id)
  end

  def open_episode
    episodes.find_by(ended_at: nil)
  end

  def episode_active_at(time)
    episodes.where(started_at: ..time)
            .where('ended_at IS NULL OR ended_at >= ?', time)
            .order(started_at: :desc)
            .first
  end

  def create_episode(trigger:, at:)
    ConversationOutcome.create!(
      account_id: @conversation.account_id,
      assistant: @assistant,
      conversation_id: @conversation.id,
      inbox_id: @conversation.inbox_id,
      episode_trigger: trigger,
      started_at: at
    )
  end

  def reply_snapshot(episode, at)
    captain_replies = public_replies(episode, at).where(sender: @assistant)
    human_replies = public_replies(episode, at)
                    .where(sender_type: 'User')
                    .reject { |message| message.content_attributes['automation_rule_id'].present? }

    {
      captain_reply_count: captain_replies.count,
      first_captain_reply_at: captain_replies.minimum(:created_at),
      last_captain_reply_at: captain_replies.maximum(:created_at),
      first_human_reply_at: human_replies.map(&:created_at).min
    }
  end

  def public_replies(episode, at)
    @conversation.messages
                 .where(message_type: :outgoing, private: false)
                 .where(created_at: episode.started_at..at)
  end

  def normalized_reason_category(reason_category)
    category = reason_category.to_s.presence
    category if ConversationOutcome::HANDOFF_REASON_CATEGORIES.include?(category)
  end
end
