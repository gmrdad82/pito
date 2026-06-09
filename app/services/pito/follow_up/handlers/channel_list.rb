# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list channels` messages (reply_target: "channel_list").
      #
      # The list stamps each channel card with its @handle, so the user can reply:
      #
      #   #<handle> visit @<channel_handle> — open the channel's YouTube page
      #                                       via a delayed auto-click.
      #
      # Mode :append — adds a new message below; the list stays follow-up-able so
      # the user can visit several channels in turn.
      class ChannelList < Pito::FollowUp::Handler
        self.target "channel_list"
        self.mode   :append
        self.actions "visit"

        def call(event:, rest:, conversation:)
          action, ref = parse_rest(rest)
          ref = ref.to_s.strip

          case action
          when "visit"
            handle_visit(ref, conversation)
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

        # ── helpers ────────────────────────────────────────────────────────────

        # Resolve a channel from a ref string by its @handle.
        #   @handle or handle (with/without leading @) → find by handle (case-insensitive)
        def resolve_channel(ref)
          # Strip leading # and whitespace (lexer may split "#9" → "# 9")
          clean = ref.sub(/\A#\s*/, "").strip
          handle_bare = clean.sub(/\A@+/, "")

          ::Channel.find_by(handle: "@#{handle_bare}") ||
            ::Channel.find_by(handle: handle_bare)
        end
      end
    end
  end
end
