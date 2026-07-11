# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for :ai answers.
      #
      #   #a7 @ai <text>  → CONTINUE the thread anchored on that answer: a new
      #                     pending :ai event whose orchestrator run guarantees
      #                     the anchored exchange (the owner's prompt + this
      #                     answer) rides in the model's context even when it
      #                     has scrolled out of the history window.
      #
      # The source :ai message stays live (consume: false) so the owner can
      # keep talking. Suggested commands are clickable/copyable content, run by
      # typing them — the old `apply` reply was dropped (owner call: one less
      # indirection). share/revoke arrive via the universal reply set.
      class AiMessage < Pito::FollowUp::Handler
        self.target "ai_message"

        AI_CONTINUE = /\A@ai\b\s*(.*)\z/im

        def call(event:, rest:, conversation:, **)
          if (m = rest.to_s.strip.match(AI_CONTINUE))
            return continue_thread(event:, prompt: m[1].strip)
          end

          action, = parse_rest(rest)
          Result::Error.new(
            message_key:  "pito.follow_up.errors.unknown_action",
            message_args: { action: action.to_s }
          )
        end

        private

        # The same pending-marker the typed `@ai` handler emits — the
        # Finalizer's ai-pending gate enqueues the orchestrator; the anchor id
        # pins this exchange into the model's context.
        def continue_thread(event:, prompt:)
          return Result::Error.new(message_key: "pito.chat.ai.needs_prompt", message_args: {}) if prompt.blank?

          payload = {
            "status" => "pending", "blocks" => [],
            "prompt" => prompt, "anchor_event_id" => event.id
          }
          Result::Append.new(events: [ { kind: :ai, payload: } ], consume: false)
        end
      end
    end
  end
end
