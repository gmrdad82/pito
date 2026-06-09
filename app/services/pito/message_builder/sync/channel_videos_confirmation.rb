# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Sync
      # Builds the payload for a "sync channel + all its videos?" confirmation.
      # The executor branch (`sync_channel_videos` in Pito::Confirmation::Executor)
      # enqueues SyncChannelVideosJob on confirm, which syncs channel fields/stats
      # AND all video fields/stats, then broadcasts a summary.
      module ChannelVideosConfirmation
        module_function

        # @param scope_label  [String]         display label (e.g. "@pito" or "all channels")
        # @param channel_ids  [Array<Integer>] resolved channel ids; empty = all
        # @param conversation [Conversation]
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(scope_label, channel_ids:, conversation:)
          payload = {
            "command"         => "sync_channel_videos",
            "body"            => Pito::Copy.render("pito.copy.sync.channel_videos_confirm", { scope: scope_label }),
            "html"            => false,
            "scope_label"     => scope_label,
            "channel_ids"     => channel_ids,
            "conversation_id" => conversation.id
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
