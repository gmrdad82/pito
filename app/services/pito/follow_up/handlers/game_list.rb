# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list games` messages (reply_target: "game_list").
      #
      # A thin shim (Phase 19): every allowed reply verb is handed to the SAME
      # chat verb handler via VerbDelegator, which resolves the reference among the
      # list's rows (T18.2) and wraps the result (T18.3) — so a reply produces the
      # identical events to the free-chat verb. No reimplementation here.
      #
      #   #<handle> show <id|title>   → the detail card + enhanced recommendations
      #   #<handle> delete | rm <id>  → the delete confirmation
      #
      # Allowed actions gate the reply (T18.5). More verbs (reindex/sync/link/
      # unlink) join `actions` as their handlers migrate.
      class GameList < Pito::FollowUp::Handler
        self.target "game_list"
        self.mode   :append
        self.actions "show", "delete", "rm"

        def call(event:, rest:, conversation:)
          Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:)
        end
      end
    end
  end
end
