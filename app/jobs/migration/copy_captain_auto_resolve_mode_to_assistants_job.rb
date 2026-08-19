class Migration::CopyCaptainAutoResolveModeToAssistantsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Captain::Assistant.includes(:account).find_each do |assistant|
      next if assistant.config.key?('auto_resolve_mode')

      assistant.update!(auto_resolve_mode: assistant.account.captain_auto_resolve_mode)
    end
  end
end
