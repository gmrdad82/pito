# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list games` messages (reply_target: "game_list").
      #
      # A thin shim: allowed reply tools are handed to ToolDelegator (show/delete/rm),
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
      # tools.yml (via Dispatch::Matrix) declares that `with`, `without`, `sort`, and `order`
      # are :mutate (no echo, no turn, re-render the same message), while the
      # class-level mode (:append) governs show/delete/rm (consume the source,
      # echo + turn).
      class GameList < Pito::FollowUp::Handler
        self.target "game_list"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          case action
          when "with", "without"
            mutate_columns(event:, conversation:, action:, args:)
          when "sort", "order"
            mutate_sort(event:, conversation:, args:)
          when "analyze"
            # `analyze #3` → analyze JUST game #3 (subject = that game's title); bare
            # `analyze` → the whole listed scope. (Bug: previously always analyzed
            # ALL listed games, so the subject read "N games".)
            refs = args.to_s.scan(/#?(\d+)/).flatten.map(&:to_i)
            ids  = refs.presence || Array(event.payload["game_ids"]).map(&:to_i)
            Pito::FollowUp::AnalyzeReply.append(level: :game, ids:, conversation:, period:)
          when "next", "more"
            list_next_games(event:, conversation:)
          else
            Pito::FollowUp::ToolDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end
        end

        private

        # Re-sort the stamped game list by a column token.
        # Strips an optional leading `by`, parses a trailing direction, and
        # resolves the sort key via Game::ListColumns.sort_key_for.  An unknown
        # or not-present column is a lenient no-op (records remain in stamped order).
        def mutate_sort(event:, conversation:, args:)
          payload = event.payload.with_indifferent_access

          current_cols       = Array(payload["list_columns"]).map(&:to_sym)
          suppressed_columns = Array(payload["suppressed_columns"]).map(&:to_sym)

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
            columns:            current_cols,
            suppressed_columns:
          )

          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]
          # Carry the continuation cursor forward AND fold in the just-applied sort so
          # `next`/`more` keeps paging in this order (#12). Only when the sort resolved
          # (key present); an unknown column is a no-op and leaves the cursor's sort.
          if payload.key?("list_cursor") && (cursor = payload["list_cursor"])
            cursor = cursor.merge("sort_token" => sort_token.presence, "sort_direction" => direction.to_s) if key
            new_payload["list_cursor"] = cursor
          end

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

          current_cols       = Array(payload["list_columns"]).map(&:to_sym)
          suppressed_columns = Array(payload["suppressed_columns"]).map(&:to_sym)
          # A per-list-suppressed column (e.g. :channels on a single-channel
          # result set) is excluded from the vocabulary for THIS mutation only
          # — "with channel" then resolves to nothing, same silent no-op as any
          # other unrecognized token (never a crash, never re-adds the column).
          vocab = Pito::MessageBuilder::Game::ListColumns.vocabulary.reject { |_, canonical| suppressed_columns.include?(canonical) }

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
            columns:            new_cols,
            suppressed_columns:
          )

          # make_followupable! is idempotent, but we need to PRESERVE the original
          # handle — not generate a new one.  Overwrite the stamped fields with the
          # original values so the same #<handle> keeps working.
          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]
          # Carry the cursor forward with the NEW column set so `next`/`more` keeps the
          # customized columns on later pages (#12).
          if payload.key?("list_cursor") && (cursor = payload["list_cursor"])
            new_payload["list_cursor"] = cursor.merge("columns" => new_cols.map(&:to_s))
          end

          Pito::FollowUp::Result::Mutation.new(
            kind:    event.kind.to_sym,
            payload: new_payload
          )
        end

        # Re-run the game list query from the cursor stored in the source event
        # payload, starting at cursor["offset"]. Returns a new list message with
        # the next batch. If no list_cursor is present (list was complete), renders
        # list_end copy.
        def list_next_games(event:, conversation:)
          payload = event.payload.with_indifferent_access
          cursor  = payload["list_cursor"]

          unless cursor
            text = Pito::Copy.render("pito.copy.list_end")
            return Pito::FollowUp::Result::Append.new(
              events: [ { kind: :system, payload: { "text" => text } } ],
              consume: false
            )
          end

          offset             = cursor["offset"].to_i
          columns            = Array(cursor["columns"]).map(&:to_sym)
          suppressed_columns = Array(cursor["suppressed_columns"]).map(&:to_sym)
          sort_token = cursor["sort_token"].presence
          sort_dir   = cursor["sort_direction"].presence

          # Rebuild the game relation — replay GameListFilter with the stored raw,
          # then the chat handler's shared query builders (the SAME code path
          # that produced page 1, so this page can never drift from it).
          all_games =
            if cursor["ranked_ids"]
              # Search results (#8): page the stored similarity ranking in order,
              # NOT a replayed list query. ranked_ids is the full ranked id list.
              ids   = Array(cursor["ranked_ids"]).map(&:to_i)
              by_id = Pito::Chat::Handlers::List.games_relation(::Game.where(id: ids), columns:).index_by(&:id)
              ids.filter_map { |id| by_id[id] }
            else
              base = Pito::Chat::GameListFilter.call(cursor["raw"].to_s)
              # Re-apply channel scope if stored.
              if cursor["channel"].present?
                ch   = Pito::Chat::Handlers::List.find_channel_by_handle(cursor["channel"])
                base = ch ? Pito::Chat::Handlers::List.games_scoped_to_channel(base, ch) : ::Game.none
              end
              Pito::Chat::Handlers::List.games_relation(base, columns:).to_a
            end

          if sort_token.present?
            key = Pito::MessageBuilder::Game::ListColumns.sort_key_for(sort_token, selected_columns: columns)
            if key
              all_games = all_games.sort_by { |g| key.call(g) }
              all_games.reverse! if sort_dir == "desc"
            end
          end

          # The cursor carries its owning tool (post-3.0.0) so per-tool page sizes
          # survive into `next`/`more` continuations instead of every cursor
          # stepping by the :list page size — a search's ranked_ids cursor pages
          # at 20, not 50. Absent "tool" == the pre-3.0.0 world (plain list
          # queries never stamped one) => default to "list"; an unrecognized
          # tool name or a tool declaring no pager also falls back to the :list
          # pager so a stale persisted cursor can never crash a `next`.
          cursor_tool = cursor["tool"].presence || "list"
          pager =
            begin
              Pito::Dispatch::Config.pager(tool: cursor_tool.to_sym)
            rescue KeyError
              nil
            end
          pager ||= Pito::Dispatch::Config.pager(tool: :list)

          page_sz = pager[:page_size]
          rows    = all_games[offset, page_sz] || []

          if rows.empty?
            text = Pito::Copy.render("pito.copy.list_end")
            return Pito::FollowUp::Result::Append.new(
              events: [ { kind: :system, payload: { "text" => text } } ],
              consume: false
            )
          end

          new_payload = Pito::MessageBuilder::Game::List.call(rows, conversation:, columns:, suppressed_columns:)

          if all_games.size > (offset + page_sz)
            new_cursor = {
              "offset"             => offset + page_sz,
              "raw"                => cursor["raw"],
              "channel"            => cursor["channel"],
              "sort_token"         => sort_token,
              "sort_direction"     => sort_dir,
              "columns"            => columns.map(&:to_s),
              "suppressed_columns" => suppressed_columns.map(&:to_s)
            }
            new_cursor["ranked_ids"] = cursor["ranked_ids"] if cursor["ranked_ids"]
            # Without carrying "tool", page 3+ would resolve the pager against
            # :list (50/page) instead of the cursor-owning tool (:search, 20).
            new_cursor["tool"] = cursor["tool"] if cursor["tool"]
            new_payload["list_cursor"] = new_cursor
            total = all_games.size
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: total,
              rest:  total - (offset + rows.size),
              tool:  Pito::Dispatch::Config.pager(tool: :list)[:more_tool]
            )
            new_payload["list_footer"] = [ new_payload["list_footer"].presence, more_text ].compact.join(" ")
          end

          # consume: false — the source list stays repliable (with/without/sort
          # still work on it, matching link/unlink and the cursor-preservation
          # contract in the mutate handlers).
          Pito::FollowUp::Result::Append.new(
            events: [ { kind: :system, payload: new_payload } ], consume: false
          )
        end
      end
    end
  end
end
