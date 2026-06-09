# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list games` messages (reply_target: "game_list").
      #
      # A thin shim: allowed reply verbs are handed to VerbDelegator (show/delete/rm),
      # which resolves the reference among the list's rows and wraps the result.
      #
      #   #<handle> show <id|title>   → the detail card + enhanced recommendations
      #   #<handle> delete | rm <id>  → the delete confirmation
      #
      # Column mutations (no consume, :mutate mode per action):
      #   #<handle> add <columns>     → rebuild list with extra column(s)
      #   #<handle> remove <columns>  → rebuild list without the named column(s)
      #
      # The action_modes DSL declares that `add` and `remove` are :mutate (no echo,
      # no turn, re-render the same message), while the class-level mode (:append)
      # governs show/delete/rm (consume the source, echo + turn).
      class GameList < Pito::FollowUp::Handler
        self.target "game_list"
        self.mode   :append
        self.action_modes add: :mutate, remove: :mutate
        self.actions "show", "delete", "rm", "add", "remove"

        def call(event:, rest:, conversation:)
          action, args = parse_rest(rest)

          case action
          when "add", "remove"
            mutate_columns(event:, conversation:, action:, args:)
          else
            Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:)
          end
        end

        private

        # Parse the comma-separated column list from args, compute the new set
        # (add: union; remove: difference), reload the same games, and rebuild
        # the list payload preserving the reply handle + target so it stays repliable.
        def mutate_columns(event:, conversation:, action:, args:)
          payload = event.payload.with_indifferent_access

          current_cols = Array(payload["list_columns"]).map(&:to_sym)
          vocab        = Pito::MessageBuilder::Game::ListColumns.vocabulary

          # Parse the requested delta columns from the comma-list.
          delta_cols = args.split(/\s*,\s*/).filter_map { |t|
            vocab[t.strip.downcase]
          }.uniq

          new_cols =
            case action
            when "add"    then (current_cols | delta_cols)
            when "remove" then (current_cols - delta_cols)
            end

          new_cols = Pito::MessageBuilder::Game::ListColumns.canonical_order(new_cols)

          # Reload games by the stamped ordered ids.
          ids   = Array(payload["game_ids"])
          games = ::Game.where(id: ids).sort_by { |g| ids.index(g.id) || ids.size }

          # Re-use the same reply_handle so the message stays repliable.
          new_payload = Pito::MessageBuilder::Game::List.call(
            games,
            conversation:,
            columns:      new_cols
          )

          # make_followupable! is idempotent, but we need to PRESERVE the original
          # handle — not generate a new one.  Overwrite the stamped fields with the
          # original values so the same #<handle> keeps working.
          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]

          Pito::FollowUp::Result::Mutation.new(
            kind:    event.kind.to_sym,
            payload: new_payload
          )
        end
      end
    end
  end
end
