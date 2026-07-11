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
      def chat(messages:, model:, tools: nil, system: nil, effort: nil)
        raise Error, "api key missing" if @api_key.blank?

        response = post(build_body(messages:, model:, tools:, system:, effort:))
        parse(response, model:)
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
        request = Net::HTTP::Post.new(uri)
        apply_auth(request)
        request["anthropic-version"] = ANTHROPIC_VERSION
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = JSON.generate(body)

        Net::HTTP.start(uri.hostname, uri.port,
                         use_ssl: uri.scheme == "https",
                         open_timeout: OPEN_TIMEOUT,
                         read_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end
      rescue StandardError => e
        raise Error, "Anthropic request failed: #{e.class}: #{e.message}"
      end

      def apply_auth(request)
        if @auth == "x_api_key"
          request["x-api-key"] = @api_key
        else
          request["Authorization"] = "Bearer #{@api_key}"
        end
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
