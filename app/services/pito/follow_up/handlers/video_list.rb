# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list videos` messages (reply_target: "video_list").
      #
      # A thin shim (Phase 19): every allowed reply verb is handed to the SAME
      # chat verb handler via VerbDelegator, which resolves the reference among the
      # list's rows (T18.2 — entity type fixed to VIDEO by this reply_target) and
      # wraps the result (T18.3). No reimplementation.
      #
      #   #<handle> show <id|title>  → the video detail card + enhanced message
      #   #<handle> rm | delete <id> → the video delete confirmation
      #
      # More verbs (publish/unlist/schedule/reindex/sync/link/unlink) join
      # `actions` as their handlers migrate onto the backbone.
      class VideoList < Pito::FollowUp::Handler
        self.target "video_list"
        self.mode   :append
        self.actions "show", "delete", "rm"

        def call(event:, rest:, conversation:)
          Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:)
        end
      end
    end
  end
end
