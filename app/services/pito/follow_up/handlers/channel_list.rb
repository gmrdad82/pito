# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list channels` messages (reply_target: "channel_list").
      #
      # The list stamps each channel card with its id and @handle, so the user
      # can reply:
      #
      #   #<handle> visit @<channel_handle>   — open the channel's YouTube page
      #                                         via a delayed auto-click.
      #   #<handle> visit <id>                — same, resolved by numeric id.
      #
      #   #<handle> reindex @<channel_handle> — re-embed ALL of the channel's videos
      #                                         by enqueuing VideoVoyageIndexJob for
      #                                         each one (async batch). Mode: :append.
      #
      # Mode :append — adds a new message below; the list stays follow-up-able so
      # the user can visit or reindex several channels in turn.
      class ChannelList < Pito::FollowUp::Handler
        self.target "channel_list"
        self.mode   :append
        self.actions "visit", "reindex"

        def call(event:, rest:, conversation:)
          action, ref = parse_rest(rest)
          ref = ref.to_s.strip

          case action
          when "visit"
            handle_visit(ref, conversation)
          when "reindex"
            handle_reindex(ref, conversation)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_list.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # ── visit ──────────────────────────────────────────────────────────────

        def handle_visit(ref, conversation)
          channel = resolve_channel(ref)

          unless channel
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_list.errors.not_found",
              message_args: { ref: ref }
            )
          end

          Pito::FollowUp::Result::Append.new(events: [
            { kind: "system", payload: Pito::MessageBuilder::Channel::Visit.call(channel, conversation: conversation) }
          ])
        end

        # ── reindex ────────────────────────────────────────────────────────────

        def handle_reindex(ref, conversation)
          channel = resolve_channel(ref)

          unless channel
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_list.errors.not_found",
              message_args: { ref: ref }
            )
          end

          payload = Pito::MessageBuilder::Channel::ReindexConfirmation.call(channel, conversation:)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "confirmation", payload: payload } ]
          )
        end

        # ── helpers ────────────────────────────────────────────────────────────

        # Resolve a channel from a ref string.
        #   @handle or handle (with/without @) → find by handle
        #   digits                              → find by id
        def resolve_channel(ref)
          # Strip leading # and whitespace (lexer may split "#9" → "# 9")
          clean = ref.sub(/\A#\s*/, "").strip

          if clean.match?(/\A\d+\z/)
            ::Channel.find_by(id: clean)
          else
            # Try the exact value (may or may not have @), then without @, then with @
            handle_bare = clean.sub(/\A@+/, "")
            ::Channel.find_by(handle: "@#{handle_bare}") ||
              ::Channel.find_by(handle: handle_bare)
          end
        end
      end
    end
  end
end
