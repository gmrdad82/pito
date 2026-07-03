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
          when "sort", "order"
            mutate_sort(event:, args: ref)
          when "analyze"
            # `analyze @handle` → analyze JUST that channel (subject = its handle);
            # bare `analyze` → the whole listed scope. Same single-subject fix as
            # the vid/game lists.
            Pito::FollowUp::AnalyzeReply.append(
              level: :channel, ids: analyze_channel_ids(event, ref), conversation:, period:
            )
          when "next"
            list_next_channels(event:, conversation:)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_list.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

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

          key = Pito::MessageBuilder::Channel::ListColumns.sort_key_for(tokens.join(" "))
          if key
            channels = channels.sort_by { |c| key.call(c) }
            channels.reverse! if direction == :desc
          end

          new_payload = Pito::MessageBuilder::Channel::List.call(channels, conversation: event.conversation)
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

          if sort_token.present?
            key = Pito::MessageBuilder::Channel::ListColumns.sort_key_for(sort_token)
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

          new_payload = Pito::MessageBuilder::Channel::List.call(rows, conversation:)

          if all_channels.size > (offset + page_sz)
            new_cursor = {
              "offset"         => offset + page_sz,
              "sort_token"     => sort_token,
              "sort_direction" => sort_dir
            }
            new_payload["list_cursor"] = new_cursor
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
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
