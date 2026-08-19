class Captain::InboxPendingConversationsResolutionSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    CaptainInbox.includes(:inbox).find_each do |captain_inbox|
      Captain::InboxPendingConversationsResolutionJob.perform_later(captain_inbox.inbox)
    end
  end
end
