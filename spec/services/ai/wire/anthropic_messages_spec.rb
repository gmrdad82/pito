# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Wire::AnthropicMessages, type: :service do
  let(:base_url) { "https://anthropic.example/v1" }
  let(:endpoint) { "#{base_url}/messages" }
  let(:api_key) { "sk-test" }

  let(:json_headers) { { "Content-Type" => "application/json" } }
  let(:minimal_success_body) do
    {
      content:     [ { type: "text", text: "hola" } ],
      stop_reason: "end_turn",
      usage:       { input_tokens: 7, output_tokens: 3 }
    }.to_json
  end

  def build_adapter(auth: "x_api_key", reasoning: "none", key: api_key)
    described_class.new(base_url: base_url, api_key: key, auth: auth, reasoning: reasoning)
  end

  describe "#chat" do
    context "happy text path" do
      it "returns a Response with text, no tool_calls, total usage, and stop_reason :stop" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    {
            content:     [ { type: "text", text: "hola" } ],
            stop_reason: "end_turn",
            usage:       { input_tokens: 7, output_tokens: 3 }
          }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x")

        expect(response.text).to eq("hola")
        expect(response.tool_calls).to eq([])
        expect(response.usage.total).to eq(10)
        expect(response.stop_reason).to eq(:stop)
      end
    end

    context "mixed content blocks" do
      it "joins text blocks in order and skips thinking blocks" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    {
            content:     [
              { type: "thinking", thinking: "working it out..." },
              { type: "text", text: "a" },
              { type: "text", text: "b" }
            ],
            stop_reason: "end_turn",
            usage:       { input_tokens: 1, output_tokens: 1 }
          }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x")

        expect(response.text).to eq("ab")
      end
    end

    context "tool-use path" do
      it "returns one ToolCall with the parsed Hash input and stop_reason :tool_use" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    {
            content:     [
              { type: "tool_use", id: "t1", name: "pito_show", input: { "noun" => "game", "ref" => "3" } }
            ],
            stop_reason: "tool_use",
            usage:       { input_tokens: 1, output_tokens: 1 }
          }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [ { role: "user", content: "show game 3" } ], model: "claude-x")

        expect(response.tool_calls.size).to eq(1)
        tool_call = response.tool_calls.first
        expect(tool_call.id).to eq("t1")
        expect(tool_call.name).to eq("pito_show")
        expect(tool_call.arguments).to eq({ "noun" => "game", "ref" => "3" })
        expect(response.stop_reason).to eq(:tool_use)
      end

      it "defaults arguments to {} when input is nil" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    {
            content:     [ { type: "tool_use", id: "t2", name: "pito_noop", input: nil } ],
            stop_reason: "tool_use",
            usage:       { input_tokens: 1, output_tokens: 1 }
          }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [], model: "claude-x")

        expect(response.tool_calls.first.arguments).to eq({})
      end
    end

    context "request body" do
      it "sends a fixed max_tokens of 8192" do
        stub = stub_request(:post, endpoint).with { |request|
          JSON.parse(request.body)["max_tokens"] == 8192
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x")

        expect(stub).to have_been_requested
      end

      it "sends system as a top-level field when given" do
        stub = stub_request(:post, endpoint).with { |request|
          JSON.parse(request.body)["system"] == "be terse"
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x", system: "be terse")

        expect(stub).to have_been_requested
      end

      it "omits system when not given" do
        stub = stub_request(:post, endpoint).with { |request|
          !JSON.parse(request.body).key?("system")
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x")

        expect(stub).to have_been_requested
      end

      it "passes tools through verbatim, including input_schema" do
        tools = [
          { name: "pito_show", description: "Show a resource",
            input_schema: { type: "object", properties: { noun: { type: "string" } }, required: [ "noun" ] } }
        ]

        stub = stub_request(:post, endpoint).with { |request|
          JSON.parse(request.body)["tools"] == JSON.parse(tools.to_json)
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x", tools: tools)

        expect(stub).to have_been_requested
      end

      it "builds a thinking block from budget_tokens for a 'budget' reasoning provider at effort 'medium'" do
        stub = stub_request(:post, endpoint).with { |request|
          JSON.parse(request.body)["thinking"] == { "type" => "enabled", "budget_tokens" => 8192 }
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(reasoning: "budget").chat(
          messages: [ { role: "user", content: "hey" } ], model: "claude-x", effort: "medium"
        )

        expect(stub).to have_been_requested
      end

      it "omits thinking when effort is nil, even for a 'budget' reasoning provider" do
        stub = stub_request(:post, endpoint).with { |request|
          !JSON.parse(request.body).key?("thinking")
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(reasoning: "budget").chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x")

        expect(stub).to have_been_requested
      end

      it "omits thinking for a 'none' reasoning provider even when effort is given" do
        stub = stub_request(:post, endpoint).with { |request|
          !JSON.parse(request.body).key?("thinking")
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(reasoning: "none").chat(
          messages: [ { role: "user", content: "hey" } ], model: "claude-x", effort: "high"
        )

        expect(stub).to have_been_requested
      end
    end

    context "auth" do
      it "sends x-api-key and anthropic-version 2023-06-01 by default" do
        stub = stub_request(:post, endpoint)
               .with(headers: { "x-api-key" => api_key, "anthropic-version" => "2023-06-01" })
               .to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(auth: "x_api_key").chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x")

        expect(stub).to have_been_requested
      end

      it "sends Authorization: Bearer <key> when auth is 'bearer'" do
        stub = stub_request(:post, endpoint)
               .with(headers: { "Authorization" => "Bearer #{api_key}" })
               .to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(auth: "bearer").chat(messages: [ { role: "user", content: "hey" } ], model: "claude-x")

        expect(stub).to have_been_requested
      end
    end

    context "blank api key" do
      it "raises Ai::Wire::Error and makes no request" do
        stub = stub_request(:post, endpoint)

        expect {
          build_adapter(key: "").chat(messages: [], model: "claude-x")
        }.to raise_error(Ai::Wire::Error)
        expect(stub).not_to have_been_requested
      end
    end

    context "non-2xx response" do
      it "raises Ai::Wire::Error carrying the 429 status" do
        stub_request(:post, endpoint).to_return(status: 429, body: "rate limited")

        expect { build_adapter.chat(messages: [], model: "claude-x") }.to raise_error(Ai::Wire::Error) { |error|
          expect(error.status).to eq(429)
        }
      end
    end

    context "network timeout" do
      it "raises Ai::Wire::Error" do
        stub_request(:post, endpoint).to_timeout

        expect { build_adapter.chat(messages: [], model: "claude-x") }.to raise_error(Ai::Wire::Error)
      end
    end

    context "malformed response body JSON" do
      it "raises Ai::Wire::Error" do
        stub_request(:post, endpoint).to_return(status: 200, body: "not json{", headers: json_headers)

        expect { build_adapter.chat(messages: [], model: "claude-x") }.to raise_error(Ai::Wire::Error)
      end
    end

    context "stop_reason normalization" do
      it "maps max_tokens to :length" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    { content: [], stop_reason: "max_tokens", usage: { input_tokens: 1, output_tokens: 1 } }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [], model: "claude-x")

        expect(response.stop_reason).to eq(:length)
      end

      it "maps an unrecognized stop_reason to :other" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    { content: [], stop_reason: "something_new", usage: { input_tokens: 1, output_tokens: 1 } }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [], model: "claude-x")

        expect(response.stop_reason).to eq(:other)
      end
    end

    context "usage tracking" do
      it "reports usage to Pito::Stack on a successful call" do
        stub_request(:post, endpoint).to_return(status: 200, body: minimal_success_body, headers: json_headers)

        expect(Pito::Stack).to receive(:track).with("ai", hash_including(units: 10))

        build_adapter.chat(messages: [], model: "claude-x")
      end
    end
  end
end
