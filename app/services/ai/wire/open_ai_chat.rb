# frozen_string_literal: true

module Ai
  module Wire
    # OpenAI-compatible chat-completions wire — the request/response shape
    # shared by every provider whose API mirrors OpenAI's `/chat/completions`
    # (OpenCode Zen, OpenAI itself, OpenRouter, DeepSeek, Qwen, HuggingFace's
    # router, …). These providers differ only in base_url, auth header style,
    # and reasoning-parameter shape — all three come from the caller
    # (Ai::ProviderRegistry), never hardcoded here. One adapter, N providers.
    #
    # One #chat call = one POST, normalized to Ai::Wire::Response so the
    # orchestrator never touches a provider's raw JSON. Every failure mode —
    # missing key, non-2xx, network/timeout, malformed JSON — raises
    # Ai::Wire::Error; nothing is swallowed to nil, because the orchestrator
    # (not this adapter) owns retry/backoff policy.
    class OpenAiChat
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 120

      # OpenAI `finish_reason` values not listed here (and nil) normalize to
      # :other — new provider-specific reasons fail safe rather than raise.
      STOP_REASONS = {
        "stop" => :stop,
        "tool_calls" => :tool_use,
        "length" => :length
      }.freeze

      # @param base_url [String] e.g. "https://opencode.ai/zen/v1" (no
      #   trailing slash) — POSTs to "#{base_url}/chat/completions".
      # @param api_key [String] provider API key; blank raises on #chat.
      # @param auth [String] "bearer" (Authorization: Bearer <key>) or
      #   "x_api_key" (x-api-key: <key>) — Ai::ProviderRegistry's `auth`.
      # @param reasoning [String] the provider's `reasoning` capability —
      #   "effort" | "passthrough" | "none" — controls how `effort` maps
      #   onto the request body (see #reasoning_params).
      def initialize(base_url:, api_key:, auth: "bearer", reasoning: "none")
        @base_url = base_url
        @api_key = api_key
        @auth = auth
        @reasoning = reasoning
      end

      # @param messages [Array<Hash>] {role:, content:, ...} passed through
      #   verbatim — this adapter never inspects or rewrites message content.
      # @param model [String] provider model id.
      # @param tools [Array<Hash>, nil] {name:, description:, input_schema:}
      #   (JSON Schema Hash) — mapped to the OpenAI `tools` function shape.
      # @param system [String, nil] prepended as a leading system message.
      # @param effort [String, nil] "low" | "medium" | "high" | nil.
      # @return [Ai::Wire::Response]
      # @raise [Ai::Wire::Error] missing key, non-2xx, network/timeout, or a
      #   response body that fails to parse as the expected JSON shape.
      def chat(messages:, model:, tools: nil, system: nil, effort: nil)
        raise Error, "api key missing" if @api_key.blank?

        payload = request_body(messages: messages, model: model, tools: tools, system: system, effort: effort)
        http_response = post_chat_completions(payload)
        build_response(http_response, model: model)
      end

      # The assistant turn that carries a Response's tool calls, in THIS wire's
      # native history shape — the orchestrator appends it before the results.
      # (Each wire encodes tool traffic differently; the loop never builds these
      # hashes itself.)
      def assistant_tool_message(response)
        {
          role:       "assistant",
          content:    response.text.presence,
          tool_calls: response.tool_calls.map do |tc|
            { id: tc.id, type: "function",
              function: { name: tc.name, arguments: JSON.generate(tc.arguments) } }
          end
        }
      end

      # One executed tool's markdown result, in this wire's native shape. The
      # OpenAI shape has no error flag — the error reads as content, which the
      # model handles fine (`error:` kept for signature parity with the sibling).
      def tool_result_message(tool_call, content, error: false) # rubocop:disable Lint/UnusedMethodArgument
        { role: "tool", tool_call_id: tool_call.id, content: content.to_s }
      end

      private

      def request_body(messages:, model:, tools:, system:, effort:)
        body = { model: model, messages: full_messages(messages, system) }
        body.merge!(tool_params(tools)) if tools.present?
        body.merge!(reasoning_params(effort))
        body
      end

      def full_messages(messages, system)
        return messages if system.blank?

        [ { role: "system", content: system } ] + messages
      end

      def tool_params(tools)
        {
          tools: tools.map do |tool|
            { type: "function", function: { name: tool[:name], description: tool[:description], parameters: tool[:input_schema] } }
          end,
          tool_choice: "auto"
        }
      end

      # "effort" providers take a top-level `reasoning_effort` string;
      # "passthrough" providers take a nested `reasoning: {effort:}` Hash;
      # "none" (or an absent `effort`) sends nothing — omitting the key
      # entirely is how these APIs mean "let the model decide".
      def reasoning_params(effort)
        return {} if effort.blank?

        case @reasoning
        when "effort"      then { reasoning_effort: effort }
        when "passthrough" then { reasoning: { effort: effort } }
        else {}
        end
      end

      def post_chat_completions(payload)
        uri = URI.parse("#{@base_url}/chat/completions")
        request = Net::HTTP::Post.new(uri)
        apply_auth(request)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(payload)

        Net::HTTP.start(uri.hostname, uri.port,
                         use_ssl: uri.scheme == "https",
                         open_timeout: OPEN_TIMEOUT,
                         read_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end
      rescue StandardError => e
        raise Error, "Ai::Wire::OpenAiChat request failed: #{e.class}: #{e.message}"
      end

      def apply_auth(request)
        case @auth
        when "bearer"   then request["Authorization"] = "Bearer #{@api_key}"
        when "x_api_key" then request["x-api-key"] = @api_key
        end
      end

      def build_response(http_response, model:)
        raise_on_error!(http_response)

        parsed = JSON.parse(http_response.body)
        message = parsed.dig("choices", 0, "message") || {}
        usage = build_usage(parsed["usage"])

        response = Response.new(
          text: message["content"].to_s,
          tool_calls: build_tool_calls(message["tool_calls"]),
          usage: usage,
          stop_reason: normalize_stop_reason(parsed.dig("choices", 0, "finish_reason"))
        )

        Pito::Stack.track("ai", endpoint: "#{URI(@base_url).host}/#{model}", units: usage.total)
        response
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "Ai::Wire::OpenAiChat response parse failed: #{e.class}: #{e.message}"
      end

      def raise_on_error!(http_response)
        return if http_response.is_a?(Net::HTTPSuccess)

        raise Error.new("#{http_response.code} #{http_response.message}",
                         status: http_response.code.to_i, body: http_response.body)
      end

      def build_tool_calls(tool_calls)
        Array(tool_calls).map do |call|
          function = call["function"] || {}
          ToolCall.new(id: call["id"], name: function["name"], arguments: parse_arguments(function["arguments"]))
        end
      end

      # Malformed argument JSON becomes {} rather than raising — a broken
      # tool call is the model's problem to fix on the next turn, not a
      # reason to blow up the whole chat turn.
      def parse_arguments(arguments_json)
        return {} if arguments_json.blank?

        parsed = JSON.parse(arguments_json)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def build_usage(usage)
        Usage.new(input_tokens: usage&.dig("prompt_tokens").to_i, output_tokens: usage&.dig("completion_tokens").to_i)
      end

      def normalize_stop_reason(finish_reason)
        STOP_REASONS.fetch(finish_reason, :other)
      end
    end
  end
end
