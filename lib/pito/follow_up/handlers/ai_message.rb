# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for :ai answers.
      #
      #   #a7 @ai <text>          → CONTINUE the thread anchored on that
      #                             answer. Routes through the SAME
      #                             target-agnostic path every OTHER rostered
      #                             card's `@ai` reply takes (ToolDelegator ->
      #                             the uniform Router contract ->
      #                             Chat::Handlers::Ai, which stamps
      #                             anchor_event_id from follow_up.source_event
      #                             -- see its class header): a new pending
      #                             :ai event whose orchestrator run
      #                             guarantees the anchored exchange (the
      #                             owner's prompt + this answer) rides in
      #                             the model's context even when it has
      #                             scrolled out of the history window.
      #                             NOTHING ai_message-specific happens here
      #                             anymore.
      #   #a7 apply|use|accept    → STAGE the answer's suggested command. The
      #                             web client intercepts this token BEFORE it
      #                             ever reaches the server (chat_form_
      #                             controller.js clicks the answer's accept
      #                             chip — the [data-pito-use-widget-fill]
      #                             span, no POST). This handler only runs for
      #                             the non-web fallback: it hands the command
      #                             text back as a plain system message for
      #                             the owner to copy/type themselves — it
      #                             NEVER executes the command. This is
      #                             ai_message's own EXTRA action: every other
      #                             declared action here is `@ai`.
      #
      # The source :ai message stays live (consume: false -- Chat::Handlers::Ai
      # forces it on every reply, regardless of target) so the owner can keep
      # talking. share/revoke arrive via the universal reply set.
      class AiMessage < Pito::FollowUp::Handler
        self.target "ai_message"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, = parse_rest(rest)
          return undeclared_action(action) unless declared?(action)

          if action == "@ai"
            return Pito::FollowUp::ToolDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end

          apply_fallback(event:)
        end

        private

        # Non-web fallback for apply/use/accept — the web client's fast-path
        # click never reaches here. Requires a `type: "suggestion"` block in
        # the answer's payload (the same block the accept chip's command text
        # is rendered from); otherwise there is nothing to hand back.
        def apply_fallback(event:)
          suggestion = Array(event.payload["blocks"]).find { |b| b.is_a?(Hash) && b["type"].to_s == "suggestion" }
          unless suggestion
            return Result::Error.new(
              message_key:  "pito.follow_up.ai_message.errors.no_suggestion",
              message_args: {}
            )
          end

          command = suggestion["command"].to_s
          Result::Append.new(
            events: [ { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.ai.apply_fallback", command:) } ],
            consume: false
          )
        end
      end
    end
  end
end
