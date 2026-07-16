# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Nl::CompletionClient, type: :service do
  let(:base_url) { "http://127.0.0.1:8092" }
  let(:chat_endpoint) { "#{base_url}/v1/chat/completions" }
  let(:grammar) { 'root ::= "ls vids"' }
  let(:messages) do
    [
      { role: "system", content: "Rewrite the owner's words as one PITO command." },
      { role: "user", content: "show the vids" },
      { role: "assistant", content: "ls vids" },
      { role: "user", content: "ls vids" }
    ]
  end

  def set_nlmapper_url(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PITO_NLMAPPER_URL").and_return(value)
  end

  def chat_response(content)
    { choices: [ { message: { content: content } } ] }.to_json
  end

  describe "#chat" do
    context "happy path" do
      before do
        set_nlmapper_url(base_url)
        stub_request(:post, chat_endpoint)
          .with(body: hash_including(
            "messages" => [
              { "role" => "system", "content" => "Rewrite the owner's words as one PITO command." },
              { "role" => "user", "content" => "show the vids" },
              { "role" => "assistant", "content" => "ls vids" },
              { "role" => "user", "content" => "ls vids" }
            ],
            "grammar" => grammar, "n_predict" => 24, "temperature" => 0,
            "chat_template_kwargs" => { "enable_thinking" => false }
          ))
          .to_return(
            status:  200,
            body:    chat_response(" ls vids \n"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns the stripped completion text" do
        result = described_class.new.chat(messages: messages, grammar: grammar)
        expect(result).to eq("ls vids")
      end
    end

    context "when the URL is unconfigured" do
      before { set_nlmapper_url(nil) }

      it "returns nil and makes no HTTP request" do
        stub = stub_request(:post, %r{.*})
        result = described_class.new.chat(messages: messages, grammar: grammar)
        expect(result).to be_nil
        expect(stub).not_to have_been_requested
      end
    end

    context "on a non-2xx response" do
      before do
        set_nlmapper_url(base_url)
        stub_request(:post, chat_endpoint).to_return(status: 500, body: "boom")
      end

      it "returns nil without raising" do
        result = described_class.new.chat(messages: messages, grammar: grammar)
        expect(result).to be_nil
      end
    end

    context "on a timeout" do
      before do
        set_nlmapper_url(base_url)
        stub_request(:post, chat_endpoint).to_timeout
      end

      it "returns nil without raising" do
        result = described_class.new.chat(messages: messages, grammar: grammar)
        expect(result).to be_nil
      end
    end

    context "when the response body is malformed JSON" do
      before do
        set_nlmapper_url(base_url)
        stub_request(:post, chat_endpoint).to_return(status: 200, body: "not json")
      end

      it "returns nil without raising" do
        result = described_class.new.chat(messages: messages, grammar: grammar)
        expect(result).to be_nil
      end
    end

    context "when the response content is blank" do
      before do
        set_nlmapper_url(base_url)
        stub_request(:post, chat_endpoint).to_return(
          status:  200,
          body:    chat_response("   "),
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "returns nil" do
        result = described_class.new.chat(messages: messages, grammar: grammar)
        expect(result).to be_nil
      end
    end

    context "with a custom max_tokens" do
      before do
        set_nlmapper_url(base_url)
        stub_request(:post, chat_endpoint)
          .with(body: hash_including("n_predict" => 32))
          .to_return(
            status:  200,
            body:    chat_response("ls vids"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "passes max_tokens through as n_predict" do
        result = described_class.new.chat(messages: messages, grammar: grammar, max_tokens: 32)
        expect(result).to eq("ls vids")
      end
    end

    context "with a custom repeat_penalty" do
      before do
        set_nlmapper_url(base_url)
        stub_request(:post, chat_endpoint)
          .with(body: hash_including("repeat_penalty" => 1.3))
          .to_return(
            status:  200,
            body:    chat_response("ls vids"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "passes repeat_penalty through on the payload" do
        result = described_class.new.chat(messages: messages, grammar: grammar, repeat_penalty: 1.3)
        expect(result).to eq("ls vids")
      end
    end

    context "when messages is empty" do
      before { set_nlmapper_url(base_url) }

      it "returns nil and makes no HTTP request" do
        stub = stub_request(:post, %r{.*})
        result = described_class.new.chat(messages: [], grammar: grammar)
        expect(result).to be_nil
        expect(stub).not_to have_been_requested
      end
    end
  end
end
