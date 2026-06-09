# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Sync
      # Builds the payload for a "sync all videos on <scope>?" confirmation.
      # `scope_label` is the human-readable scope string (e.g. "@pito" or "all channels").
      # `channel_ids` is an Array of Channel ids to sync (empty = all channels).
      # The executor branch (`sync_videos` in Pito::Confirmation::Executor) enqueues
      # SyncVideosJob on confirm.
      module VideosConfirmation
        module_function

        # @param scope_label  [String]         display label shown in the confirmation body
        # @param channel_ids  [Array<Integer>] resolved channel ids; empty = all
        # @param conversation [Conversation]
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(scope_label, channel_ids:, conversation:)
          payload = {
            "command"         => "sync_videos",
            "body"            => Pito::Copy.render("pito.copy.sync.videos_confirm", { scope: scope_label }),
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
