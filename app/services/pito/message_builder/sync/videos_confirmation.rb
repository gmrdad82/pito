# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Sync
      # Builds the payload for a "sync all videos on <scope>?" confirmation.
      # `scope_label` is the human-readable scope string (e.g. "@pito" or "all channels").
      # `channel_ids` is an Array of Channel ids to sync (empty = all channels).
      # `video_ids` is an optional Array of local Video ids to restrict the sync to
      #   specific videos; empty (default) means sync all videos in scope.
      # The executor branch (`sync_videos` in Pito::Confirmation::Executor) enqueues
      # SyncVideosJob on confirm.
      module VideosConfirmation
        module_function

        # @param scope_label  [String]         display label shown in the confirmation body
        # @param channel_ids  [Array<Integer>] resolved channel ids; empty = all
        # @param video_ids    [Array<Integer>] optional video id restriction; empty = all
        # @param conversation [Conversation]
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(scope_label, channel_ids:, conversation:, video_ids: [])
          vids = Array(video_ids)

          if vids.any?
            # Targeted sync — name the videos, not the channel scope. The label
            # also flows to the post-sync done message, so it reads sensibly.
            scope_label = vids.map { |id| "##{id}" }.join(", ")
            body = Pito::Copy.render(
              "pito.copy.sync.videos_confirm_targeted", { vids: scope_label, count: vids.size }
            )
          else
            body = Pito::Copy.render("pito.copy.sync.videos_confirm", { scope: scope_label })
          end

          payload = {
            "command"         => "sync_videos",
            "body"            => body,
            "html"            => false,
            "scope_label"     => scope_label,
            "channel_ids"     => channel_ids,
            "video_ids"       => vids,
            "conversation_id" => conversation.id
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
