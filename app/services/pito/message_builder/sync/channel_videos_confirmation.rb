# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Sync
      # Builds the payload for a "sync channel(s) + all their videos?" confirmation.
      # Used when the `with videos` (or `with videos,…`) clause is present in
      # `sync channels with …`.
      # `with_items` carries the full parsed set of sync targets so the executor
      # can inspect them if needed in the future (e.g. analytics).
      # The executor branch (`sync_channel_videos` in Pito::Confirmation::Executor)
      # enqueues SyncChannelVideosJob on confirm, which syncs channel fields/stats
      # AND all video fields/stats, then broadcasts a summary.
      module ChannelVideosConfirmation
        module_function

        # @param scope_label  [String]         display label (e.g. "@pito" or "all channels")
        # @param channel_ids  [Array<Integer>] resolved channel ids; empty = all
        # @param with_items   [Array<Symbol>]  parsed sync targets (includes :videos)
        # @param conversation [Conversation]
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(scope_label, channel_ids:, conversation:, with_items: [])
          payload = {
            "command"         => "sync_channel_videos",
            "body"            => Pito::Copy.render("pito.copy.sync.channel_videos_confirm", { scope: scope_label }),
            "html"            => false,
            "scope_label"     => scope_label,
            "channel_ids"     => channel_ids,
            "with_items"      => Array(with_items).map(&:to_s),
            "conversation_id" => conversation.id
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
