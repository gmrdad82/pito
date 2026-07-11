# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `@ai` chat verb — the AI assistant entry point.
      #
      #   @ai <anything> → a pending :ai event; the Finalizer's ai-pending gate
      #                    enqueues AiOrchestratorJob, which runs the tool loop
      #                    against the active provider (Ai::Client) and finalizes
      #                    this event with the answer (or converts it into the
      #                    native message a pito command renders — Flow A).
      #
      # The prompt is everything after the verb, read RAW from message.raw so
      # the grammar's filler-stripping never rewrites the owner's words. The
      # same follows the pending-analytics pattern: emit a marker, return
      # immediately, let the async filler resolve this message's own thinking
      # indicator when the answer lands.
      class Ai < Pito::Chat::Handler
        self.verb = :"@ai"
        self.description_key = "pito.chat.ai.descriptions.ai"

        # "@ai what should I play" → captures "what should I play" (the parser
        # fuses + downcases the verb, but raw keeps the owner's typing: any case).
        PROMPT_PATTERN = /\A@ai\b\s*(.*)\z/im

        def call
          prompt = extract_prompt
          return needs_prompt if prompt.blank?

          payload = { "status" => "pending", "blocks" => [], "prompt" => prompt }
          Pito::Chat::Result::Ok.new(events: [ { kind: :ai, payload: } ])
        end

        private

        def extract_prompt
          m = message.raw.to_s.strip.match(PROMPT_PATTERN)
          m && m[1].strip
        end

        def needs_prompt
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.chat.ai.needs_prompt") }
          ])
        end
      end
    end
  end
end
