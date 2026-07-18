# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for :ai answers.
      #
      #   #a7 @ai <text>          → CONTINUE the thread anchored on that
      #                             answer: a new pending :ai event whose
      #                             orchestrator run guarantees the anchored
      #                             exchange (the owner's prompt + this
      #                             answer) rides in the model's context even
      #                             when it has scrolled out of the history
      #                             window.
      #   #a7 apply|use|accept    → STAGE the answer's suggested command. The
      #                             web client intercepts this token BEFORE it
      #                             ever reaches the server (chat_form_
      #                             controller.js clicks the answer's
      #                             Pito::UseWidgetComponent fill button, no
      #                             POST). This handler only runs for the
      #                             non-web fallback: it hands the command
      #                             text back as a plain system message for
      #                             the owner to copy/type themselves — it
      #                             NEVER executes the command.
      #
      # The source :ai message stays live (consume: false) so the owner can
      # keep talking. share/revoke arrive via the universal reply set.
      class AiMessage < Pito::FollowUp::Handler
        self.target "ai_message"

        AI_CONTINUE = /\A@ai\b\s*(.*)\z/im

        def call(event:, rest:, conversation:, **)
          if (m = rest.to_s.strip.match(AI_CONTINUE))
            return continue_thread(event:, prompt: m[1].strip)
          end

          action, = parse_rest(rest)
          return undeclared_action(action) unless declared?(action)

          apply_fallback(event:)
        end

        private

        # The same pending-marker the typed `@ai` handler emits — the
        # Finalizer's ai-pending gate enqueues the orchestrator; the anchor id
        # pins this exchange into the model's context.
        def continue_thread(event:, prompt:)
          # The reply form honors the SAME web opt-in flag as a fresh @ai turn
          # (`#handle @ai --web …`) — one parser, no drift.
          prompt, web = Pito::Chat::Handlers::Ai.strip_web_flag(prompt)
          return Result::Error.new(message_key: "pito.chat.ai.needs_prompt", message_args: {}) if prompt.blank?

          payload = {
            "status" => "pending", "blocks" => [],
            "prompt" => prompt, "anchor_event_id" => event.id
          }
          payload["web"] = true if web
          Result::Append.new(events: [ { kind: :ai, payload: } ], consume: false)
        end

        # Non-web fallback for apply/use/accept — the web client's fast-path
        # click never reaches here. Requires a `type: "suggestion"` block in
        # the answer's payload (the same block the UseWidgetComponent fill
        # button is rendered from); otherwise there is nothing to hand back.
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
