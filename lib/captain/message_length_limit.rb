module Captain::MessageLengthLimit
  # Hard message length limits imposed by messaging channels. Channels without
  # an entry (website, email, API) accept long-form responses and need no rewrite.
  CHANNEL_LIMITS = {
    'Channel::TwitterProfile' => 280,
    'Channel::TwilioSms' => 1600,
    'Channel::Sms' => 1600,
    'Channel::FacebookPage' => 2000,
    'Channel::Instagram' => 1000,
    'Channel::Whatsapp' => 4096,
    'Channel::Telegram' => 4096,
    'Channel::Line' => 5000
  }.freeze

  def self.for(conversation)
    return if conversation.blank?

    CHANNEL_LIMITS[conversation.inbox&.channel_type]
  end
end
