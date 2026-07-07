# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list videos` messages (reply_target: "video_list").
      #
      # A thin shim: allowed reply verbs are handed to VerbDelegator (show/delete/rm),
      # which resolves the reference among the list's rows and wraps the result.
      #
      #   #<handle> show <id|title>  → the video detail card + enhanced message
      #   #<handle> rm | delete <id> → the video delete confirmation
      #   #<handle> schedule <id> <when> → the schedule confirmation
      #   #<handle> publish | unlist <id> → the visibility-change confirmation
      #
      # Column mutations (no consume, :mutate mode per action):
      #   #<handle> with <columns>    → rebuild list with extra column(s)
      #   #<handle> without <columns> → rebuild list without the named column(s)
      #
      # Sort mutations (no consume, :mutate mode per action):
      #   #<handle> sort by <col> [desc]  → re-sort the stamped list in place
      #   #<handle> order by <col> [desc] → alias for sort
      #
      # verbs.yml (via Dispatch::Matrix) declares that `with`, `without`, `sort`, and `order`
      # are :mutate (no echo, no turn, re-render the same message), while the
      # class-level mode (:append) governs show/delete/rm (consume the source,
      # echo + turn).
      class VideoList < Pito::FollowUp::Handler
        self.target "video_list"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          case action
          when "with", "without"
            mutate_columns(event:, conversation:, action:, args:)
          when "sort", "order"
            mutate_sort(event:, conversation:, args:)
          when "analyze"
            # `analyze #3` → analyze JUST vid #3 (subject = that vid's title); bare
            # `analyze` → the whole listed scope. (Bug: previously always analyzed
            # ALL listed vids, so the subject read "N vids".)
            refs = args.to_s.scan(/#?(\d+)/).flatten.map(&:to_i)
            ids  = refs.presence || Array(event.payload["video_ids"]).map(&:to_i)
            Pito::FollowUp::AnalyzeReply.append(level: :vid, ids:, conversation:, period:)
          when "next", "more"
            list_next_videos(event:, conversation:, viewport_width:)
          else
            Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end
        end

        private

        # Re-sort the stamped video list by a column token.
        # Strips an optional leading `by`, parses a trailing direction, and
        # resolves the sort key via Video::ListColumns.sort_key_for.  An unknown
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

          # Reload videos by the stamped ordered ids.
          ids    = Array(payload["video_ids"])
          videos = ::Video.where(id: ids).sort_by { |v| ids.index(v.id) || ids.size }

          key = Pito::MessageBuilder::Video::ListColumns.sort_key_for(
            sort_token, selected_columns: current_cols
          )

          if key
            videos = videos.sort_by { |v| key.call(v) }
            videos.reverse! if direction == :desc
          end

          new_payload = Pito::MessageBuilder::Video::List.call(
            videos,
            conversation:,
            columns:      current_cols
          )

          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]
          # Carry the cursor forward AND fold in the just-applied sort so `next`/`more`
          # keeps paging in this order (#12). (Previously the sort reply dropped the
          # cursor entirely, ending pagination.)
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
        # (with: union; without: difference), reload the same videos, and rebuild
        # the list payload preserving the reply handle + target so it stays repliable.
        def mutate_columns(event:, conversation:, action:, args:)
          payload = event.payload.with_indifferent_access

          current_cols = Array(payload["list_columns"]).map(&:to_sym)
          vocab        = Pito::MessageBuilder::Video::ListColumns.vocabulary

          # Parse the requested delta columns from the comma-list.
          delta_cols = args.split(/\s*,\s*/).filter_map { |t|
            vocab[t.strip.downcase]
          }.uniq

          new_cols =
            case action
            when "with"    then (current_cols | delta_cols)
            when "without" then (current_cols - delta_cols)
            end

          # Reload videos by the stamped ordered ids.
          ids    = Array(payload["video_ids"])
          videos = ::Video.where(id: ids).sort_by { |v| ids.index(v.id) || ids.size }

          # Build the new payload via the same List builder.
          new_payload = Pito::MessageBuilder::Video::List.call(
            videos,
            conversation:,
            columns:      new_cols
          )

          # Preserve the original handle so the same #<handle> keeps working.
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

        # Re-run the video list query from the cursor stored in the source event
        # payload, starting at cursor["offset"]. Returns a new list message with
        # the next batch. If no list_cursor is present (list was complete), renders
        # list_end copy.
        def list_next_videos(event:, conversation:, viewport_width: nil)
          payload = event.payload.with_indifferent_access
          cursor  = payload["list_cursor"]

          unless cursor
            text = Pito::Copy.render("pito.copy.list_end")
            return Pito::FollowUp::Result::Append.new(
              events: [ { kind: :system, payload: { "text" => text } } ],
              consume: false
            )
          end

          offset     = cursor["offset"].to_i
          columns    = Array(cursor["columns"]).map(&:to_sym)
          # Allowlist the visibility scope before public_send — the cursor is
          # server-written, but never replay an arbitrary method name from a payload.
          filter_key = cursor["filter"]&.to_sym
          filter_key = nil unless %i[published unlisted scheduled].include?(filter_key)
          sort_token = cursor["sort_token"].presence
          sort_dir   = cursor["sort_direction"].presence

          # Rebuild the scoped relation via the chat handler's shared query
          # builders — the SAME code path that produced page 1, so this page
          # can never drift from it.
          if cursor["channel"].present?
            ch   = Pito::Chat::Handlers::List.find_channel_by_handle(cursor["channel"])
            base = ch ? ch.videos : ::Video.none
          else
            base = ::Video.all
          end

          base = base.public_send(filter_key) if filter_key

          all_videos = Pito::Chat::Handlers::List.videos_relation(base, columns:).to_a

          if sort_token.present?
            key = Pito::MessageBuilder::Video::ListColumns.sort_key_for(sort_token, selected_columns: columns)
            if key
              all_videos = all_videos.sort_by { |v| key.call(v) }
              all_videos.reverse! if sort_dir == "desc"
            end
          end

          page_sz = Pito::Dispatch::Config.pager(verb: :list)[:page_size]
          rows    = all_videos[offset, page_sz] || []

          if rows.empty?
            text = Pito::Copy.render("pito.copy.list_end")
            return Pito::FollowUp::Result::Append.new(
              events: [ { kind: :system, payload: { "text" => text } } ],
              consume: false
            )
          end

          new_payload = Pito::MessageBuilder::Video::List.call(rows, conversation:, columns:)

          if all_videos.size > (offset + page_sz)
            new_cursor = {
              "offset"         => offset + page_sz,
              "channel"        => cursor["channel"],
              "filter"         => cursor["filter"],
              "sort_token"     => sort_token,
              "sort_direction" => sort_dir,
              "columns"        => columns.map(&:to_s)
            }
            new_payload["list_cursor"] = new_cursor
            total = all_videos.size
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: total,
              rest:  total - (offset + rows.size),
              verb:  Pito::Dispatch::Config.pager(verb: :list)[:more_verb]
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
