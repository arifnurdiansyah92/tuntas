class Captain::ReportingEventListener < BaseListener
  include ReportingEventHelper

  def captain_conversation_resolved(event)
    create_captain_inference_event(event, 'conversation_captain_inference_resolved')
  end

  def captain_conversation_handed_off(event)
    create_captain_inference_event(event, 'conversation_captain_inference_handoff')
  end

  private

  def create_captain_inference_event(event, name)
    return unless event.data[:source] == 'inference'

    conversation = event.data[:conversation]
    reporting_event = ReportingEvent.new(
      name: name,
      value: event.timestamp.to_i - conversation.created_at.to_i,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      conversation_id: conversation.id,
      event_start_time: conversation.created_at,
      event_end_time: event.timestamp
    )
    reporting_event.save!
    safe_rollup(reporting_event)
  end

  def safe_rollup(reporting_event)
    ReportingEvents::RollupService.perform(reporting_event)
  rescue StandardError => e
    TuntasExceptionTracker.new(e, account: reporting_event.account).capture_exception
  end
end
