# frozen_string_literal: true

# Local completion client (3.0.0) — the nlmapper sidecar's did-you-mean
# fallback for chat input the grammar-constrained mapper can't place.
#
# Single-purpose HTTP wrapper around the llama.cpp `nlmapper` sidecar's
# OpenAI-compatible chat endpoint (see the `nlmapper` service in
# docker-compose.yml / docker-compose.dev.yml) — POST `/v1/chat/completions`
# with a grammar-constrained multi-turn `messages` array, NOT the raw
# `/completion` endpoint. Switched 2026-07-15 (live-proof): raw-completion
# prompting fed Qwen3-0.6B a bare prompt string, bypassing the instruct
# model's own chat template — the model rambled inside the grammar's charset
# (a `rm games` hallucination came out of a plain list intent).
# `/v1/chat/completions` applies Qwen3's chat template AND lets the grammar
# additionally suppress its `<think>` preamble, which is what actually
# disciplines the output.
#
# Multi-turn, not a single system+user pair (also 2026-07-15, live-proof):
# Pito::Nl::Mapper originally packed its whole few-shot corpus as `owner:
# ...\ncommand: ...` lines inside ONE system-role string. A 0.6B instruct
# model imitates ALTERNATING chat turns far better than prose exemplars
# buried in a system block — the old shape left `greet` sitting as a
# constrained-decoding attractor regardless of the utterance. Mapper now
# hands this client one system turn (the instruction) plus a real
# user/assistant PAIR per exemplar, ending on the owner's own utterance as
# the final open user turn — see Pito::Nl::Mapper#chat_messages.
#
# `Pito::Embedding::Client` is the sibling that talks to a different
# sidecar (`embedder`) over `/v1/embeddings` — mirror its structure, not
# its route.
#
# Configuration: `ENV["PITO_NLMAPPER_URL"]` (http://nlmapper:8082 in the
# production stack, http://127.0.0.1:8092 for host-Puma dev). A blank or
# absent URL means "not configured".
#
# One contract, fully forgiving BY DESIGN (K2 data honesty): this client
# sits on the cold did-you-mean path, where nil simply means "the mapper
# has no opinion" and the unknown-input copy takes over — unconfigured
# URL, non-2xx, a malformed response, a network error, or a timeout all
# degrade to nil, never raise. Callers never need a rescue.
#
# Test behaviour: WebMock blocks non-localhost HTTP in test; specs stub
# the endpoint explicitly.
module Pito
  module Nl
    class CompletionClient
      # Hard cap on how long ONE completion may hold its caller (and, in
      # practice, a ChatDispatchJob dispatch-lane thread). 30s is a CEILING,
      # not a target — a warm sidecar answers a one-line command in seconds.
      #
      # Live incident (2026-07-17, prod, 2-vCPU Hetzner box): "show me hard
      # games" soft-failed into the NL gate correctly but took 193.96s
      # end-to-end — stacked NL turns serialize at the CPU-bound llama.cpp
      # sidecar, and each queued completion burns its whole read window just
      # WAITING for the slot while Puma/SolidQueue contend for the same two
      # cores. The mapper's own single constrained re-try (see
      # Pito::Chat::Handlers::Unknown's gate, step 3) means one NL turn can
      # spend at worst ~2x this constant on completions — keep that product
      # well under the owner's patience, and NEVER raise this without
      # re-doing the dispatch-lane arithmetic in config/queue.yml.
      READ_TIMEOUT_SECONDS = 30

      # Connection establishment to a same-box/same-network sidecar — quick
      # by design; a sidecar that can't even accept a socket in 5s is down,
      # and nil-degrading beats blocking the chat turn.
      OPEN_TIMEOUT_SECONDS = 5

      # Runs a grammar-constrained chat completion and returns the generated
      # text, or nil on ANY failure. `messages` is the full OpenAI-shaped
      # turn array (`[{ role:, content: }, ...]`) the caller composed — this
      # client is deliberately low-level and opinion-free about HOW that
      # array is built (single system+user pair, multi-turn few-shot, or
      # anything else); see Pito::Nl::Mapper for the one caller that exists
      # today. `grammar` is a GBNF string (see Pito::Nl::GbnfBuilder);
      # `max_tokens` bounds `n_predict` (llama.cpp's own extension param,
      # still honored on the `/v1/chat/completions` route alongside
      # `messages`). `repeat_penalty` rides straight through to llama.cpp's
      # own sampling param (default 1.0, i.e. off — matching llama.cpp's own
      # default so every OTHER caller sees no behavior change). Live-proof,
      # 2026-07-15: Pito::Nl::Mapper's unbounded (1.0) sampling was observed
      # padding digit runs — a two-token answer like "link 14 3" kept
      # decoding past the valid command instead of stopping — so Mapper now
      # calls with 1.1 to discourage the decoder from repeating itself.
      #
      # K2 distinction (mirrors Pito::Embedding::Client's forgiving path):
      # this method never raises and never calls Appsignal.report_error.
      # Every failure here — unconfigured URL, non-2xx, malformed JSON, a
      # network error — degrades to nil BY DESIGN (the mapper's own
      # did-you-mean copy takes over), so it is not an incident; the warn
      # log (with the response code on non-2xx, for operator visibility)
      # is the right amount of noise. Reporting cold-path nils to AppSignal
      # would page/alert on expected behavior every time the mapper simply
      # has no opinion.
      def chat(messages:, grammar:, max_tokens: 24, repeat_penalty: 1.0)
        return nil if base_url.blank?
        return nil if messages.blank?

        response = perform_request(
          messages: messages, grammar: grammar, max_tokens: max_tokens, repeat_penalty: repeat_penalty
        )

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("[Pito::Nl::CompletionClient] non-2xx response: #{response.code} #{response.message}")
          return nil
        end

        content = JSON.parse(response.body).dig("choices", 0, "message", "content").to_s.strip
        content.presence
      rescue StandardError => e
        Rails.logger.warn("[Pito::Nl::CompletionClient] completion failed: #{e.class}: #{e.message}")
        nil
      end

      private

      def perform_request(messages:, grammar:, max_tokens:, repeat_penalty:)
        uri = URI.parse("#{base_url.chomp('/')}/v1/chat/completions")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        # repeat_penalty passthrough — see #chat's doc comment for the
        # 2026-07-15 live-proof rationale (unbounded sampling padded digit
        # runs; Mapper now calls with 1.3, every other caller keeps 1.0).
        #
        # chat_template_kwargs.enable_thinking: false (2026-07-15,
        # hand-verified) — Qwen3 is a thinking model; its chat template
        # emits a `<think>` reasoning preamble before the actual answer, and
        # the GBNF grammar above was strangling the model mid-think (a
        # `</think>` leak showed up in the last probe instead of a command).
        # llama.cpp forwards `chat_template_kwargs` straight into the Qwen3
        # Jinja template, which honors `enable_thinking` as its own
        # documented toggle — with it off, the same model produced `link
        # vid 14 to game 3` on the first try. Belt-and-suspenders with
        # Mapper's `/no_think` prompt suffix (see Pito::Nl::Mapper::
        # INSTRUCTION) — either alone was enough in testing, but both cost
        # nothing and guard against either mechanism silently regressing.
        request.body = JSON.generate(
          messages: messages,
          grammar: grammar, n_predict: max_tokens,
          temperature: 0, repeat_penalty: repeat_penalty,
          chat_template_kwargs: { enable_thinking: false }
        )

        Pito::Stack.track("nlmapper", endpoint: "chat_completions", units: 1)
        # Timeouts: see READ_TIMEOUT_SECONDS / OPEN_TIMEOUT_SECONDS (the
        # 2026-07-17 193.96s incident rationale lives on the constants).
        Net::HTTP.start(uri.hostname, uri.port,
                        use_ssl: uri.scheme == "https",
                        open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: READ_TIMEOUT_SECONDS) do |http|
          http.request(request)
        end
      end

      def base_url
        ENV["PITO_NLMAPPER_URL"]
      end
    end
  end
end
