# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list channels` messages (reply_target: "channel_list").
      #
      # The list stamps each channel card with its @handle, so the user can reply:
      #
      #   #<handle> shinies @<channel_handle> — show achievements for the channel.
      #
      # To visit a channel's YouTube page or Studio, first `show channel @<handle>`
      # then reply `#<card_handle> visit channel` or `#<card_handle> visit studio`.
      #
      # Column mutations (no consume, :mutate — vids/games parity, G26.2):
      #
      #   #<handle> with <columns>    → rebuild list with extra column(s)
      #   #<handle> without <columns> → rebuild list without the named column(s)
      #
      # Sort mutations (no consume, :mutate mode per action — vids/games parity):
      #
      #   #<handle> sort by <col> [desc]  → re-sort the stamped table in place
      #   #<handle> order by <col> [desc] → alias for sort
      #
      # Mode :append — adds a new message below; the list stays follow-up-able so
      # the user can query several channels in turn.
      class ChannelList < Pito::FollowUp::Handler
        self.target "channel_list"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, ref = parse_rest(rest)

          case action
          when "shinies"
            Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          when "with", "without"
            mutate_columns(event:, action:, args: ref)
          when "sort", "order"
            mutate_sort(event:, args: ref)
          when "analyze"
            # `analyze @handle` → analyze JUST that channel (subject = its handle);
            # bare `analyze` → the whole listed scope. Same single-subject fix as
            # the vid/game lists.
            Pito::FollowUp::AnalyzeReply.append(
              level: :channel, ids: analyze_channel_ids(event, ref), conversation:, period:
            )
          when "next", "more"
            list_next_channels(event:, conversation:)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_list.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # Parse the comma-separated column list, compute the new addable set
        # (with: union; without: difference), reload the stamped channels, and
        # rebuild the payload preserving handle/target/cursor — mirrors
        # VideoList#mutate_columns.
        def mutate_columns(event:, action:, args:)
          payload = event.payload.with_indifferent_access

          current_cols = Array(payload["list_columns"]).map(&:to_sym)
          vocab        = Pito::MessageBuilder::Channel::ListColumns.vocabulary

          delta_cols = args.to_s.split(/\s*,\s*/).filter_map { |t|
            vocab[t.strip.downcase]
          }.uniq

          new_cols = action == "with" ? (current_cols | delta_cols) : (current_cols - delta_cols)

          ids      = Array(payload["channel_ids"])
          channels = ::Channel.where(id: ids).includes(:youtube_connection)
                              .sort_by { |c| ids.index(c.id) || ids.size }

          new_payload = Pito::MessageBuilder::Channel::List.call(
            channels, conversation: event.conversation, columns: new_cols
          )
          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]
          new_payload["list_cursor"]  = payload["list_cursor"] if payload.key?("list_cursor")

          Pito::FollowUp::Result::Mutation.new(kind: event.kind.to_sym, payload: new_payload)
        end

        # Re-sort the stamped channels table by a column token — mirrors the
        # vids/games list sort replies: strip an optional leading `by`, parse a
        # trailing direction, resolve via Channel::ListColumns. An unknown column
        # is a lenient no-op (rows stay in stamped order), matching VideoList.
        def mutate_sort(event:, args:)
          payload = event.payload.with_indifferent_access

          tokens = args.to_s.strip.split(/\s+/)
          tokens.shift if tokens.first&.downcase == "by"

          direction = :asc
          if tokens.last&.downcase&.match?(/\A(?:desc|descending)\z/)
            direction = :desc
            tokens.pop
          elsif tokens.last&.downcase&.match?(/\A(?:asc|ascending)\z/)
            tokens.pop
          end

          ids      = Array(payload["channel_ids"])
          channels = ::Channel.where(id: ids).includes(:youtube_connection)
                              .sort_by { |c| ids.index(c.id) || ids.size }

          # G82 made counter sorting VISIBILITY-gated — without the stamped
          # selection every subs/views/vids sort resolved nil and the reply
          # silently no-opped (owner 2026-07-05). The stamped columns also ride
          # into the rebuild so a `with likes` selection survives the sort.
          selected = Array(payload["list_columns"]).map(&:to_sym)
          key = Pito::MessageBuilder::Channel::ListColumns.sort_key_for(
            tokens.join(" "), selected_columns: selected
          )
          if key
            channels = channels.sort_by { |c| key.call(c) }
            channels.reverse! if direction == :desc
          end

          new_payload = Pito::MessageBuilder::Channel::List.call(
            channels, conversation: event.conversation, columns: selected
          )
          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]
          # Preserve the continuation cursor — mutate replies operate on the current
          # page's channel_ids and cannot recompute the next-batch cursor. Carry it
          # forward so #handle next still works after a sort mutation on a capped list.
          new_payload["list_cursor"]  = payload["list_cursor"] if payload.key?("list_cursor")

          Pito::FollowUp::Result::Mutation.new(kind: event.kind.to_sym, payload: new_payload)
        end

        # `@handle` ref → that channel's id (if it's in the list); blank ref → all
        # listed channel ids.
        def analyze_channel_ids(event, ref)
          all = Array(event.payload["channel_ids"]).map(&:to_i)
          return all if ref.to_s.strip.blank?

          norm  = ref.to_s.sub(/\A@+/, "").downcase
          match = ::Channel.where(id: all).find { |c| c.handle.to_s.sub(/\A@+/, "").downcase == norm }
          match ? [ match.id ] : all
        end

        # Re-run the channel list query from the cursor stored in the source event
        # payload, starting at cursor["offset"]. Returns a new list message with
        # the next batch. If no list_cursor is present (list was complete), renders
        # list_end copy.
        def list_next_channels(event:, conversation:)
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
          sort_token = cursor["sort_token"].presence
          sort_dir   = cursor["sort_direction"].presence

          # The chat handler's shared query builder — the SAME code path that
          # produced page 1, so this page can never drift from it.
          all_channels = Pito::Chat::Handlers::List.channels_relation.to_a

          # G125.4 (TUI contract catch): the stamped column selection must ride
          # into `next` exactly like it rides into `sort` — without it, counter
          # sorts silently no-op past page 1 (sort_key_for is visibility-gated)
          # and a `with`-customized table resets to defaults on the next page.
          selected = Array(payload["list_columns"]).map(&:to_sym)

          if sort_token.present?
            key = Pito::MessageBuilder::Channel::ListColumns.sort_key_for(
              sort_token, selected_columns: selected
            )
            if key
              all_channels = all_channels.sort_by { |c| key.call(c) }
              all_channels.reverse! if sort_dir == "desc"
            end
          end

          page_sz = Pito::Dispatch::Config.pager(verb: :list)[:page_size]
          rows    = all_channels[offset, page_sz] || []

          if rows.empty?
            text = Pito::Copy.render("pito.copy.list_end")
            return Pito::FollowUp::Result::Append.new(
              events: [ { kind: :system, payload: { "text" => text } } ],
              consume: false
            )
          end

          new_payload = Pito::MessageBuilder::Channel::List.call(
            rows, conversation:,
            columns: selected.presence || Pito::MessageBuilder::Channel::ListColumns::DEFAULT_COLUMNS
          )

          if all_channels.size > (offset + page_sz)
            new_cursor = {
              "offset"         => offset + page_sz,
              "sort_token"     => sort_token,
              "sort_direction" => sort_dir
            }
            new_payload["list_cursor"] = new_cursor
            total = all_channels.size
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: total,
              rest:  total - (offset + rows.size),
              verb:  Pito::Dispatch::Config.pager(verb: :list)[:more_verb]
            )
            existing_footer = new_payload["list_footer"].to_s.presence
            new_payload["list_footer"] = [ existing_footer, more_text ].compact.join(" ")
          end

          # consume: false — the source list stays repliable (sort still works
          # on it, matching the cursor-preservation contract in mutate_sort).
          Pito::FollowUp::Result::Append.new(
            events: [ { kind: :system, payload: new_payload } ], consume: false
          )
        end
      end
    end
  end
end
