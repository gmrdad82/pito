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
    #
    # Pass a BLOCK to #chat to stream: the same POST goes out with
    # `stream: true`, the SSE events are folded up as they arrive, and each
    # tool-call arguments fragment is yielded live — the return value is the
    # very same assembled Response either way, so callers opt into streaming
    # without changing anything downstream of the call.
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
      # @yield [tool_name, args_fragment] OPTIONAL — streams when given. Each
      #   tool-call arguments fragment is yielded raw as it arrives, with the
      #   call's function name so far (nil until the stream has named it).
      #   Without a block the call is the plain single-JSON request/response.
      # @return [Ai::Wire::Response] the same assembled shape on both paths.
      # @raise [Ai::Wire::Error] missing key, non-2xx, network/timeout, or a
      #   response body that fails to parse as the expected JSON shape.
      def chat(messages:, model:, tools: nil, system: nil, effort: nil, &on_arguments_fragment)
        raise Error, "api key missing" if @api_key.blank?

        payload = request_body(messages: messages, model: model, tools: tools, system: system, effort: effort)
        return build_response(post_chat_completions(payload), model: model) unless on_arguments_fragment

        stream_response(payload, model: model, on_arguments_fragment: on_arguments_fragment)
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
        uri, request = build_post(payload)

        start_http(uri) { |http| http.request(request) }
      rescue StandardError => e
        raise Error, "Ai::Wire::OpenAiChat request failed: #{e.class}: #{e.message}"
      end

      def build_post(payload)
        uri = URI.parse("#{@base_url}/chat/completions")
        request = Net::HTTP::Post.new(uri)
        apply_auth(request)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(payload)
        [ uri, request ]
      end

      def start_http(uri, &block)
        Net::HTTP.start(uri.hostname, uri.port,
                         use_ssl: uri.scheme == "https",
                         open_timeout: OPEN_TIMEOUT,
                         read_timeout: READ_TIMEOUT, &block)
      end

      # --- streaming (block-form #chat) ---------------------------------

      # Same POST as the plain path plus the two streaming body keys, read
      # back as SSE. Events fold into `state` as they arrive (the caller's
      # block sees each raw arguments fragment live); at stream end the
      # SAME assembled Response comes back — streaming is a transport
      # detail, never a different result shape.
      def stream_response(payload, model:, on_arguments_fragment:)
        state = { text: +"", tool_calls: {}, usage: nil, finish_reason: nil }

        stream_chat_completions(stream_payload(payload)) do |event|
          apply_stream_event(state, event, on_arguments_fragment: on_arguments_fragment)
        end

        usage = build_usage(state[:usage])
        response = Response.new(
          text: state[:text],
          tool_calls: assemble_stream_tool_calls(state[:tool_calls]),
          usage: usage,
          stop_reason: normalize_stop_reason(state[:finish_reason])
        )

        Pito::Stack.track("ai", endpoint: "#{URI(@base_url).host}/#{model}", units: usage.total)
        response
      end

      # `stream_options.include_usage` makes the provider close the stream
      # with a final usage-bearing event — without it token counts (and the
      # provider-reported cost) never arrive on the streaming path.
      def stream_payload(payload)
        payload.merge(stream: true, stream_options: { include_usage: true })
      end

      # Block-form Net::HTTP request so the body is consumed as it arrives.
      # With a block-form request the status is only knowable inside the
      # block — check it BEFORE reading events, because a non-2xx body is an
      # error document, not an SSE stream. Chunk boundaries are arbitrary,
      # so lines are cut from a rolling buffer, never from the raw chunk.
      def stream_chat_completions(payload)
        uri, request = build_post(payload)

        start_http(uri) do |http|
          http.request(request) do |http_response|
            raise_on_stream_error!(http_response)

            buffer = +""
            http_response.read_body do |chunk|
              buffer << chunk
              while (line = buffer.slice!(/\A[^\n]*\n/))
                event = parse_sse_event(line)
                yield event if event
              end
            end
            event = parse_sse_event(buffer) # a final line may lack its newline
            yield event if event
          end
        end
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "Ai::Wire::OpenAiChat request failed: #{e.class}: #{e.message}"
      end

      def raise_on_stream_error!(http_response)
        return if http_response.is_a?(Net::HTTPSuccess)

        raise Error.new("#{http_response.code} #{http_response.message}",
                         status: http_response.code.to_i, body: http_response.read_body)
      end

      # One SSE line → parsed event Hash, or nil for everything that isn't
      # one: blank keep-alives, non-`data:` fields, the `[DONE]` sentinel,
      # and malformed JSON (skipped — one broken event must not kill the
      # stream).
      def parse_sse_event(line)
        data = line.strip
        return nil unless data.start_with?("data:")

        data = data.delete_prefix("data:").strip
        return nil if data.empty? || data == "[DONE]"

        JSON.parse(data)
      rescue JSON::ParserError
        nil
      end

      # Folds one event into the running state. Text deltas append;
      # tool-call deltas accumulate per-index (OpenAI splits one call's
      # argument JSON across many deltas, correlated by `index`); `usage`
      # and `finish_reason` arrive on late events and simply overwrite.
      def apply_stream_event(state, event, on_arguments_fragment:)
        state[:usage] = event["usage"] if event["usage"]
        choice = event.dig("choices", 0) || {}
        state[:finish_reason] = choice["finish_reason"] if choice["finish_reason"]

        delta = choice["delta"] || {}
        state[:text] << delta["content"] if delta["content"]
        Array(delta["tool_calls"]).each do |call_delta|
          accumulate_tool_call_delta(state[:tool_calls], call_delta, on_arguments_fragment: on_arguments_fragment)
        end
      end

      # Whenever a delta carries an arguments fragment, the caller's block
      # gets it raw, with the call's function name so far — nil until a
      # delta has named the call.
      def accumulate_tool_call_delta(calls, call_delta, on_arguments_fragment:)
        call = calls[call_delta["index"].to_i] ||= { id: nil, name: nil, arguments: +"" }
        function = call_delta["function"] || {}
        call[:id] = call_delta["id"] if call_delta["id"]
        call[:name] = function["name"] if function["name"]
        return unless (fragment = function["arguments"])

        call[:arguments] << fragment
        on_arguments_fragment.call(call[:name], fragment)
      end

      # Deltas arrive index-ordered but sort anyway — the wire promises
      # nothing. Each call's joined argument JSON goes through the SAME
      # parse_arguments as the non-stream path (malformed → {}).
      def assemble_stream_tool_calls(calls)
        calls.keys.sort.map do |index|
          call = calls[index]
          ToolCall.new(id: call[:id], name: call[:name], arguments: parse_arguments(call[:arguments]))
        end
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
        Usage.new(
          input_tokens:  usage&.dig("prompt_tokens").to_i,
          output_tokens: usage&.dig("completion_tokens").to_i,
          # OpenCode Zen / OpenRouter report the call's USD cost in usage.
          cost: usage&.dig("cost")&.to_f
        )
      end

      def normalize_stop_reason(finish_reason)
        STOP_REASONS.fetch(finish_reason, :other)
      end
    end
  end
end
