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
      #   #<handle> with <columns>     → rebuild list with extra column(s)
      #   #<handle> without <columns>  → rebuild list without the named column(s)
      #
      # Sort mutations (no consume, :mutate mode per action):
      #   #<handle> sort by <col> [desc]  → re-sort the stamped list in place
      #   #<handle> order by <col> [desc] → alias for sort
      #
      # The action_modes DSL declares that `with`, `without`, `sort`, and `order`
      # are :mutate (no echo, no turn, re-render the same message), while the
      # class-level mode (:append) governs show/delete/rm (consume the source,
      # echo + turn).
      class GameList < Pito::FollowUp::Handler
        self.target "game_list"
        self.mode   :append
        self.action_modes with: :mutate, without: :mutate, sort: :mutate, order: :mutate
        self.actions "show", "delete", "del", "rm", "with", "without", "sort", "order", "link", "unlink", "platform", "price", "shinies", "analyze"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          case action
          when "with", "without"
            mutate_columns(event:, conversation:, action:, args:)
          when "sort", "order"
            mutate_sort(event:, conversation:, args:)
          when "analyze"
            # Analyze the listed games as a scope (mirrors `analyze games #…`).
            Pito::FollowUp::AnalyzeReply.append(
              level: :game, ids: Array(event.payload["game_ids"]).map(&:to_i),
              conversation:, period:
            )
          else
            Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end
        end

        private

        # Re-sort the stamped game list by a column token.
        # Strips an optional leading `by`, parses a trailing direction, and
        # resolves the sort key via Game::ListColumns.sort_key_for.  An unknown
        # or not-present column is a lenient no-op (records remain in stamped order).
        def mutate_sort(event:, conversation:, args:)
          payload = event.payload.with_indifferent_access

          current_cols = Array(payload["list_columns"]).map(&:to_sym)

          # Strip optional leading "by" particle.
          tokens = args.to_s.strip.split(/\s+/)
          tokens.shift if tokens.first&.downcase == "by"

          # Parse trailing direction token.
          direction = :asc
          if tokens.last&.downcase&.match?(/\A(?:desc|descending)\z/)
            direction = :desc
            tokens.pop
          elsif tokens.last&.downcase&.match?(/\A(?:asc|ascending)\z/)
            tokens.pop
          end

          sort_token = tokens.join(" ")

          # Reload games by the stamped ordered ids.
          ids   = Array(payload["game_ids"])
          games = ::Game.where(id: ids).sort_by { |g| ids.index(g.id) || ids.size }

          key = Pito::MessageBuilder::Game::ListColumns.sort_key_for(
            sort_token, selected_columns: current_cols
          )

          if key
            games = games.sort_by { |g| key.call(g) }
            games.reverse! if direction == :desc
          end

          new_payload = Pito::MessageBuilder::Game::List.call(
            games,
            conversation:,
            columns:      current_cols
          )

          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]
          # Lift the re-rendered (mutated) segment onto the surface background.
          new_payload["surface"]      = true

          Pito::FollowUp::Result::Mutation.new(
            kind:    event.kind.to_sym,
            payload: new_payload
          )
        end

        # Parse the comma-separated column list from args, compute the new set
        # (with: union; without: difference), reload the same games, and rebuild
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
            when "with"    then (current_cols | delta_cols)
            when "without" then (current_cols - delta_cols)
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
          # Lift the re-rendered (mutated) segment onto the surface background.
          new_payload["surface"]      = true

          Pito::FollowUp::Result::Mutation.new(
            kind:    event.kind.to_sym,
            payload: new_payload
          )
        end
      end
    end
  end
end
