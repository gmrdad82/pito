# frozen_string_literal: true

module Ai
  module Wire
    # The Anthropic Messages API wire adapter — POST `{base_url}/messages`.
    # Same public signature as the sibling `Ai::Wire::OpenAiChat` so
    # `Ai::Client` can swap wires per provider config without the
    # orchestrator caring which one is live:
    #
    #   Ai::Wire::AnthropicMessages.new(base_url:, api_key:, auth:, reasoning:)
    #     .chat(messages:, model:, tools: nil, system: nil, effort: nil)
    #     # => Ai::Wire::Response
    #
    # `auth` picks the header style: "x_api_key" sends `x-api-key: <key>`
    # (Anthropic's native scheme); any other value (namely "bearer") sends
    # `Authorization: Bearer <key>`. `reasoning` is this wire's configured
    # capability from ai_providers.yml — only "budget" ever turns `effort`
    # into a `thinking` block; every other value leaves `thinking` off.
    #
    # `#chat` also takes an optional block — the streaming form, sharing the
    # `{ |tool_name, args_fragment| }` contract with `Ai::Wire::OpenAiChat`:
    # the request gains `"stream": true`, the SSE events are folded into the
    # SAME Response the no-block path returns, and every tool_use
    # `input_json_delta` fragment is yielded live to the caller.
    class AnthropicMessages
      ANTHROPIC_VERSION = "2023-06-01"
      MAX_TOKENS = 8192
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 120

      # Fixed token budgets for the "budget"-style reasoning capability —
      # Anthropic's `thinking.budget_tokens` has no notion of low/medium/high,
      # so this wire owns the mapping from PITO's `effort` vocabulary.
      BUDGET_TOKENS = {
        "low" => 2048,
        "medium" => 8192,
        "high" => 16384
      }.freeze

      STOP_REASONS = {
        "end_turn" => :stop,
        "tool_use" => :tool_use,
        "max_tokens" => :length
      }.freeze

      def initialize(base_url:, api_key:, auth:, reasoning:)
        @base_url  = base_url
        @api_key   = api_key
        @auth      = auth.to_s
        @reasoning = reasoning.to_s
      end

      # One completed API call → Ai::Wire::Response. Raises Ai::Wire::Error on
      # a missing key, non-2xx response, or any network/parse failure.
      #
      # No block → one buffered POST, exactly as before. Block given → the
      # same call streamed: `"stream": true` is added to the body, the SSE
      # events are parsed as they arrive, and each tool_use argument fragment
      # (`input_json_delta.partial_json`) is yielded as
      # `(tool_name, args_fragment)` before the assembled Response returns.
      def chat(messages:, model:, tools: nil, system: nil, effort: nil, &block)
        raise Error, "api key missing" if @api_key.blank?

        body = build_body(messages:, model:, tools:, system:, effort:)
        return parse(post(body), model:) unless block

        stream_chat(body.merge(stream: true), model:, &block)
      end

      # The assistant turn that carries a Response's tool calls, in THIS wire's
      # native history shape — the orchestrator appends it before the results.
      def assistant_tool_message(response)
        blocks = []
        blocks << { type: "text", text: response.text } if response.text.present?
        blocks += response.tool_calls.map do |tc|
          { type: "tool_use", id: tc.id, name: tc.name, input: tc.arguments }
        end
        { role: "assistant", content: blocks }
      end

      # One executed tool's markdown result — Anthropic carries results as
      # user-role tool_result blocks with a first-class error flag.
      def tool_result_message(tool_call, content, error: false)
        { role: "user", content: [
          { type: "tool_result", tool_use_id: tool_call.id, content: content.to_s, is_error: error }
        ] }
      end

      private

      def build_body(messages:, model:, tools:, system:, effort:)
        body = { model: model, max_tokens: MAX_TOKENS, messages: messages }
        body[:system] = system if system.present?
        body[:tools] = tools if tools.present?

        thinking = build_thinking(effort)
        body[:thinking] = thinking if thinking

        body
      end

      def build_thinking(effort)
        return nil unless @reasoning == "budget"
        return nil if effort.blank?

        budget_tokens = BUDGET_TOKENS[effort.to_s]
        return nil unless budget_tokens

        { type: "enabled", budget_tokens: budget_tokens }
      end

      def post(body)
        uri = URI.parse("#{@base_url}/messages")
        request = build_request(uri, body, accept: "application/json")

        start_http(uri) { |http| http.request(request) }
      rescue StandardError => e
        raise Error, "Anthropic request failed: #{e.class}: #{e.message}"
      end

      def build_request(uri, body, accept:)
        request = Net::HTTP::Post.new(uri)
        apply_auth(request)
        request["anthropic-version"] = ANTHROPIC_VERSION
        request["Content-Type"] = "application/json"
        request["Accept"] = accept
        request.body = JSON.generate(body)
        request
      end

      def start_http(uri, &)
        Net::HTTP.start(uri.hostname, uri.port,
                         use_ssl: uri.scheme == "https",
                         open_timeout: OPEN_TIMEOUT,
                         read_timeout: READ_TIMEOUT, &)
      end

      def apply_auth(request)
        if @auth == "x_api_key"
          request["x-api-key"] = @api_key
        else
          request["Authorization"] = "Bearer #{@api_key}"
        end
      end

      # -- streaming (block-form #chat) ------------------------------------

      # Folds one SSE stream into the same Response shape #parse builds. The
      # fold state is a plain Hash: `:blocks` maps each content-block index to
      # its accumulator (text buffer, or tool_use id/name + raw-JSON argument
      # buffer); the rest mirrors the non-stream envelope fields.
      def stream_chat(body, model:, &block)
        state = { blocks: {}, input_tokens: 0, output_tokens: 0, stop_reason: nil }

        stream_post(body) { |data| fold_event(state, data, &block) }

        build_streamed_response(state, model:)
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "Anthropic stream failed: #{e.class}: #{e.message}"
      end

      # POSTs the streaming body and yields each SSE `data:` payload in wire
      # order. The status line is checked BEFORE any event is consumed — a
      # non-2xx raises without ever invoking the caller's block.
      def stream_post(body)
        uri = URI.parse("#{@base_url}/messages")
        request = build_request(uri, body, accept: "text/event-stream")

        start_http(uri) do |http|
          http.request(request) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              raise Error.new("Anthropic non-2xx response: #{response.code} #{response.message}",
                               status: response.code.to_i, body: response.body)
            end

            each_sse_data(response) { |data| yield data }
          end
        end
      end

      # SSE framing: events are `event:`/`data:` line groups separated by a
      # blank line. Chunk boundaries fall anywhere, so this buffers until a
      # full event is present; a trailing unterminated event is flushed after
      # the body ends.
      def each_sse_data(response, &)
        buffer = +""
        response.read_body do |chunk|
          buffer << chunk
          while (boundary = buffer.index("\n\n"))
            emit_sse_data(buffer.slice!(0, boundary + 2), &)
          end
        end
        emit_sse_data(buffer, &)
      end

      def emit_sse_data(raw_event)
        data = raw_event.lines.filter_map { |line| line[/\Adata: (.*)/, 1] }.join
        yield data if data.present?
      end

      # One parsed SSE event → fold-state mutation. `content_block_stop`,
      # `message_stop`, and `ping` carry nothing to fold — assembly happens
      # once the stream ends.
      def fold_event(state, data, &block)
        event = JSON.parse(data)

        case event["type"]
        when "message_start"
          state[:input_tokens] = event.dig("message", "usage", "input_tokens").to_i
        when "content_block_start"
          start_block(state, event)
        when "content_block_delta"
          fold_delta(state, event, &block)
        when "message_delta"
          fold_message_delta(state, event)
        end
      end

      def start_block(state, event)
        content_block = event["content_block"] || {}

        state[:blocks][event["index"]] =
          if content_block["type"] == "tool_use"
            { type: "tool_use", id: content_block["id"], name: content_block["name"], json: +"" }
          else
            { type: content_block["type"], text: +"" }
          end
      end

      # `text_delta` accumulates prose; `input_json_delta` accumulates a tool
      # block's raw argument JSON AND yields the fragment live to the caller
      # as `(tool_name, args_fragment)`. Other delta types (thinking_delta,
      # signature_delta, …) are skipped — parity with the non-stream path,
      # which only reads text and tool_use blocks.
      def fold_delta(state, event, &block)
        accumulator = state[:blocks][event["index"]]
        return unless accumulator

        delta = event["delta"] || {}
        case delta["type"]
        when "text_delta"
          accumulator[:text] << delta["text"].to_s if accumulator[:type] == "text"
        when "input_json_delta"
          return unless accumulator[:type] == "tool_use"

          fragment = delta["partial_json"].to_s
          accumulator[:json] << fragment
          block.call(accumulator[:name], fragment)
        end
      end

      def fold_message_delta(state, event)
        state[:output_tokens] = event.dig("usage", "output_tokens").to_i
        stop_reason = event.dig("delta", "stop_reason")
        state[:stop_reason] = stop_reason if stop_reason
      end

      def build_streamed_response(state, model:)
        blocks = state[:blocks].keys.sort.map { |index| state[:blocks][index] }

        text = blocks.select { |b| b[:type] == "text" }.map { |b| b[:text] }.join
        tool_calls = blocks.select { |b| b[:type] == "tool_use" }.map do |b|
          ToolCall.new(id: b[:id], name: b[:name], arguments: parse_streamed_arguments(b[:json]))
        end

        usage = Usage.new(input_tokens: state[:input_tokens], output_tokens: state[:output_tokens])
        Pito::Stack.track("ai", endpoint: "#{URI(@base_url).host}/#{model}", units: usage.total)

        Response.new(
          text: text,
          tool_calls: tool_calls,
          usage: usage,
          stop_reason: STOP_REASONS.fetch(state[:stop_reason], :other)
        )
      end

      # The joined fragment buffer parsed with the same tolerance the wires
      # already apply to tool arguments: blank, malformed, or non-Hash JSON
      # becomes {} rather than raising — a broken tool call is the model's
      # problem to fix on the next turn, not a reason to blow up the turn.
      def parse_streamed_arguments(json)
        return {} if json.blank?

        parsed = JSON.parse(json)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def parse(response, model:)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error.new("Anthropic non-2xx response: #{response.code} #{response.message}",
                           status: response.code.to_i, body: response.body)
        end

        build_response(JSON.parse(response.body), model: model)
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "Anthropic response parse failed: #{e.class}: #{e.message}"
      end

      def build_response(parsed, model:)
        content = Array(parsed["content"]).select { |block| block.is_a?(Hash) }

        text = content.select { |block| block["type"] == "text" }
                       .map { |block| block["text"].to_s }
                       .join

        tool_calls = content.select { |block| block["type"] == "tool_use" }
                             .map do |block|
                               ToolCall.new(id: block["id"], name: block["name"], arguments: block["input"] || {})
                             end

        usage_data = parsed["usage"] || {}
        usage = Usage.new(
          input_tokens: usage_data["input_tokens"].to_i,
          output_tokens: usage_data["output_tokens"].to_i
        )

        Pito::Stack.track("ai", endpoint: "#{URI(@base_url).host}/#{model}", units: usage.total)

        Response.new(
          text: text,
          tool_calls: tool_calls,
          usage: usage,
          stop_reason: STOP_REASONS.fetch(parsed["stop_reason"], :other)
        )
      end
    end
  end
end
