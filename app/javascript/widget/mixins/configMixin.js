export default {
  computed: {
    useInboxAvatarForBot() {
      return this.channelConfig.enabledFeatures.includes(
        'use_inbox_avatar_for_bot'
      );
    },
    hasAConnectedAgentBot() {
      return !!window.tuntasWebChannel.hasAConnectedAgentBot;
    },
    inboxAvatarUrl() {
      return window.tuntasWebChannel.avatarUrl;
    },
    channelConfig() {
      return window.tuntasWebChannel;
    },
    hasEmojiPickerEnabled() {
      return this.channelConfig.enabledFeatures.includes('emoji_picker');
    },
    hasAttachmentsEnabled() {
      return this.channelConfig.enabledFeatures.includes('attachments');
    },
    hasEndConversationEnabled() {
      return this.channelConfig.enabledFeatures.includes('end_conversation');
    },
    preChatFormEnabled() {
      return window.tuntasWebChannel.preChatFormEnabled;
    },
    preChatFormOptions() {
      let preChatMessage = '';
      const options = window.tuntasWebChannel.preChatFormOptions || {};
      preChatMessage = options.pre_chat_message;
      const { pre_chat_fields: preChatFields = [] } = options;
      return {
        preChatMessage,
        preChatFields,
      };
    },
    shouldShowPreChatForm() {
      const { preChatFields } = this.preChatFormOptions;
      // Check if at least one enabled field in pre-chat fields
      const hasEnabledFields =
        preChatFields.filter(field => field.enabled).length > 0;
      return this.preChatFormEnabled && hasEnabledFields;
    },
  },
};
