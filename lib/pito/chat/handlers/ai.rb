# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `@ai` chat tool — the AI assistant entry point.
      #
      #   @ai <anything> → a pending :ai event; the Finalizer's ai-pending gate
      #                    enqueues AiOrchestratorJob, which runs the tool loop
      #                    against the active provider (Ai::Client) and finalizes
      #                    this event with the answer (or converts it into the
      #                    native message a pito command renders — Flow A).
      #
      # The prompt is everything after the tool, read RAW from message.raw so
      # the grammar's filler-stripping never rewrites the owner's words. The
      # same follows the pending-analytics pattern: emit a marker, return
      # immediately, let the async filler resolve this message's own thinking
      # indicator when the answer lands.
      class Ai < Pito::Chat::Handler
        self.tool = :"@ai"
        self.description_key = "pito.chat.ai.descriptions.ai"

        # "@ai what should I play" → captures "what should I play" (the parser
        # fuses + downcases the tool, but raw keeps the owner's typing: any case).
        PROMPT_PATTERN = /\A@ai\b\s*(.*)\z/im

        # Strips the declared web opt-in flag (tools.yml "@ai".chat.web_flag)
        # from a prompt. Shared with the ai_message REPLY handler so
        # `#handle @ai --web …` opts in exactly like a fresh `@ai --web …`
        # (smoke-found: the reply path used to ignore the flag).
        # @return [prompt, web] — the flag-free prompt and the opt-in boolean
        def self.strip_web_flag(prompt)
          flag = Pito::Dispatch::Config.tool(:"@ai").dig(:chat, :web_flag)
          return [ prompt, false ] if flag.blank?

          pattern = /(\A|\s)#{Regexp.escape(flag)}(\s|\z)/
          return [ prompt, false ] unless prompt.to_s.match?(pattern)

          [ prompt.gsub(pattern, " ").squish, true ]
        end

        def call
          prompt, web = self.class.strip_web_flag(extract_prompt)
          return needs_prompt if prompt.blank?

          payload = { "status" => "pending", "blocks" => [], "prompt" => prompt }
          # Explicit per-message opt-in (tools.yml web_flag): only then does the
          # orchestrator hand the model the web_search/web_fetch pair.
          payload["web"] = true if web
          Pito::Chat::Result::Ok.new(events: [ { kind: :ai, payload: } ])
        end

        private

        # The opt-in flag as DECLARED in tools.yml ("@ai".chat.web_flag) — nil
        # when the ontology drops it (feature off).
        def web_flag
          Pito::Dispatch::Config.tool(:"@ai").dig(:chat, :web_flag)
        rescue KeyError
          nil
        end

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
