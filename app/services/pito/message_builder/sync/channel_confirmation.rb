# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Sync
      # Builds the payload for a "sync channel(s) info?" confirmation.
      # The executor branch (`sync_channel` in Pito::Confirmation::Executor) enqueues
      # SyncChannelJob on confirm, which syncs channel fields + stats and broadcasts
      # a summary.
      module ChannelConfirmation
        module_function

        # @param scope_label  [String]         display label (e.g. "@pito" or "all channels")
        # @param channel_ids  [Array<Integer>] resolved channel ids; empty = all
        # @param conversation [Conversation]
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(scope_label, channel_ids:, conversation:)
          payload = {
            "command"         => "sync_channel",
            "body"            => Pito::Copy.render("pito.copy.sync.channel_confirm", { scope: scope_label }),
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
