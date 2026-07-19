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
      #
      # ONE target-agnostic path serves BOTH entry points (the uniform
      # dispatch contract, Pito::Dispatch::Router): a fresh `@ai <text>` and
      # a `#<handle> @ai <text>` reply on ANY rostered card (list/detail/
      # analyze/…, tools.yml "@ai".reply.targets) run this SAME #call —
      # only `follow_up?` differs. A reply stamps `anchor_event_id` from the
      # replied-to card so AiOrchestratorJob pins that exchange into the
      # model's context (Ai::History's must_include_turn) and projects its
      # REAL content under an explicit ANCHOR block (Ai::Projector) — no
      # per-target branch here or anywhere downstream.
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
          # A reply anchors the orchestrator's history + prompt context on the
          # card it replied to (AiOrchestratorJob#anchor_turn / #anchor_addendum)
          # — target-agnostic: follow_up.source_event is ANY rostered card, not
          # only a prior :ai answer. Free chat has no follow_up, so this is a
          # no-op there.
          payload["anchor_event_id"] = follow_up.source_event.id if follow_up?
          # A reply never consumes its source card — Chat::Result::Ok#consume
          # is read only by the follow-up adapter (ChatResultAdapter) and
          # ignored on free chat, so this line changes nothing there and keeps
          # every rostered card repliable for further questions everywhere else.
          Pito::Chat::Result::Ok.new(events: [ { kind: :ai, payload: } ], consume: false)
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

        # Blank prompt. Fresh chat keeps the friendly system nudge; a reply
        # keeps the ERROR chrome a bare `#<handle> @ai` has always answered
        # with on ai_message — the same for every rostered target (entry-point
        # split, never a per-target one). ChatResultAdapter carries the Error
        # through, so the source card stays repliable for a retry.
        def needs_prompt
          if follow_up?
            return Pito::Chat::Result::Error.new(message_key: "pito.chat.ai.needs_prompt", message_args: {})
          end

          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.chat.ai.needs_prompt") }
          ])
        end
      end
    end
  end
end
