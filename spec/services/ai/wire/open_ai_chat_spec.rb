# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Wire::OpenAiChat, type: :service do
  let(:base_url) { "https://zen.example/v1" }
  let(:endpoint) { "#{base_url}/chat/completions" }
  let(:api_key) { "sk-test" }

  let(:json_headers) { { "Content-Type" => "application/json" } }
  let(:minimal_success_body) do
    {
      choices: [ { message: { content: "hi" }, finish_reason: "stop" } ],
      usage: { prompt_tokens: 10, completion_tokens: 5 }
    }.to_json
  end

  def build_adapter(auth: "bearer", reasoning: "none", key: api_key)
    described_class.new(base_url: base_url, api_key: key, auth: auth, reasoning: reasoning)
  end

  describe "#chat" do
    context "happy text path" do
      it "returns a Response with text, no tool_calls, total usage, and stop_reason :stop" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    {
            choices: [ { message: { content: "hi" }, finish_reason: "stop" } ],
            usage:   { prompt_tokens: 10, completion_tokens: 5 }
          }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "gpt-test")

        expect(response.text).to eq("hi")
        expect(response.tool_calls).to eq([])
        expect(response.usage.total).to eq(15)
        expect(response.stop_reason).to eq(:stop)
      end
    end

    context "tool-call path" do
      it "returns one ToolCall with parsed Hash arguments and stop_reason :tool_use" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    {
            choices: [ {
              message:       {
                tool_calls: [ { id: "c1", function: { name: "pito_list", arguments: '{"noun":"games"}' } } ]
              },
              finish_reason: "tool_calls"
            } ],
            usage:   { prompt_tokens: 10, completion_tokens: 5 }
          }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [ { role: "user", content: "list games" } ], model: "gpt-test")

        expect(response.tool_calls.size).to eq(1)
        tool_call = response.tool_calls.first
        expect(tool_call.id).to eq("c1")
        expect(tool_call.name).to eq("pito_list")
        expect(tool_call.arguments).to eq({ "noun" => "games" })
        expect(response.stop_reason).to eq(:tool_use)
      end
    end

    context "malformed tool-call arguments JSON" do
      it "substitutes {} for that ToolCall's arguments instead of raising" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    {
            choices: [ {
              message:       {
                tool_calls: [ { id: "c1", function: { name: "pito_list", arguments: "{not valid json" } } ]
              },
              finish_reason: "tool_calls"
            } ],
            usage:   {}
          }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [], model: "gpt-test")

        expect(response.tool_calls.first.arguments).to eq({})
      end
    end

    context "request body" do
      it "prepends the system prompt as the first message with role system" do
        stub = stub_request(:post, endpoint).with { |request|
          JSON.parse(request.body)["messages"] == [
            { "role" => "system", "content" => "be terse" },
            { "role" => "user", "content" => "hey" }
          ]
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "gpt-test", system: "be terse")

        expect(stub).to have_been_requested
      end

      it "maps tools to the OpenAI function shape plus tool_choice auto" do
        tools = [ { name: "pito_list", description: "list stuff", input_schema: { type: "object" } } ]

        stub = stub_request(:post, endpoint).with { |request|
          body = JSON.parse(request.body)
          body["tools"] == [
            { "type" => "function", "function" => { "name" => "pito_list", "description" => "list stuff", "parameters" => { "type" => "object" } } }
          ] && body["tool_choice"] == "auto"
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter.chat(messages: [ { role: "user", content: "hey" } ], model: "gpt-test", tools: tools)

        expect(stub).to have_been_requested
      end

      it "sends a top-level reasoning_effort for an 'effort' reasoning provider" do
        stub = stub_request(:post, endpoint).with { |request|
          JSON.parse(request.body)["reasoning_effort"] == "high"
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(reasoning: "effort").chat(
          messages: [ { role: "user", content: "hey" } ], model: "gpt-test", effort: "high"
        )

        expect(stub).to have_been_requested
      end

      it "sends a nested reasoning hash for a 'passthrough' reasoning provider" do
        stub = stub_request(:post, endpoint).with { |request|
          JSON.parse(request.body)["reasoning"] == { "effort" => "high" }
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(reasoning: "passthrough").chat(
          messages: [ { role: "user", content: "hey" } ], model: "gpt-test", effort: "high"
        )

        expect(stub).to have_been_requested
      end

      it "sends neither reasoning key for a 'none' reasoning provider" do
        stub = stub_request(:post, endpoint).with { |request|
          body = JSON.parse(request.body)
          !body.key?("reasoning_effort") && !body.key?("reasoning")
        }.to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(reasoning: "none").chat(
          messages: [ { role: "user", content: "hey" } ], model: "gpt-test", effort: "high"
        )

        expect(stub).to have_been_requested
      end
    end

    context "auth" do
      it "sends Authorization: Bearer <key> for bearer auth" do
        stub = stub_request(:post, endpoint)
               .with(headers: { "Authorization" => "Bearer #{api_key}" })
               .to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(auth: "bearer").chat(messages: [ { role: "user", content: "hey" } ], model: "gpt-test")

        expect(stub).to have_been_requested
      end

      it "sends x-api-key: <key> for x_api_key auth" do
        stub = stub_request(:post, endpoint)
               .with(headers: { "x-api-key" => api_key })
               .to_return(status: 200, body: minimal_success_body, headers: json_headers)

        build_adapter(auth: "x_api_key").chat(messages: [ { role: "user", content: "hey" } ], model: "gpt-test")

        expect(stub).to have_been_requested
      end
    end

    context "blank api key" do
      it "raises Ai::Wire::Error and makes no request" do
        stub = stub_request(:post, endpoint)

        expect {
          build_adapter(key: "").chat(messages: [], model: "gpt-test")
        }.to raise_error(Ai::Wire::Error)
        expect(stub).not_to have_been_requested
      end
    end

    context "non-2xx response" do
      it "raises Ai::Wire::Error carrying the status and a body excerpt" do
        stub_request(:post, endpoint).to_return(status: 401, body: "unauthorized: bad key")

        expect { build_adapter.chat(messages: [], model: "gpt-test") }.to raise_error(Ai::Wire::Error) { |error|
          expect(error.status).to eq(401)
          expect(error.message).to include("unauthorized: bad key")
        }
      end
    end

    context "network timeout" do
      it "raises Ai::Wire::Error" do
        stub_request(:post, endpoint).to_timeout

        expect { build_adapter.chat(messages: [], model: "gpt-test") }.to raise_error(Ai::Wire::Error)
      end
    end

    context "malformed response body JSON" do
      it "raises Ai::Wire::Error" do
        stub_request(:post, endpoint).to_return(status: 200, body: "not json{", headers: json_headers)

        expect { build_adapter.chat(messages: [], model: "gpt-test") }.to raise_error(Ai::Wire::Error)
      end
    end

    context "response without usage" do
      it "returns zeroed Usage without raising" do
        stub_request(:post, endpoint).to_return(
          status:  200,
          body:    { choices: [ { message: { content: "hi" }, finish_reason: "stop" } ] }.to_json,
          headers: json_headers
        )

        response = build_adapter.chat(messages: [], model: "gpt-test")

        expect(response.usage.total).to eq(0)
      end
    end

    context "usage tracking" do
      it "reports usage to Pito::Stack on a successful call" do
        stub_request(:post, endpoint).to_return(status: 200, body: minimal_success_body, headers: json_headers)

        expect(Pito::Stack).to receive(:track).with("ai", hash_including(units: 15))

        build_adapter.chat(messages: [], model: "gpt-test")
      end
    end
  end
end
