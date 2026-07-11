# frozen_string_literal: true

require "rails_helper"

# The agentic loop, exercised against a SCRIPTED client (no HTTP): each example
# hands the job a fixed sequence of Ai::Wire::Response turns and asserts what
# the pending :ai event becomes. Tool executions run through the REAL
# Ai::ToolExecutor → Pito::Mcp::Executor path (read-only against the test DB).
RSpec.describe AiOrchestratorJob do
  let(:conversation) { Conversation.singleton }

  # Minimal stand-in honoring Ai::Client's loop-facing API. Messages passed to
  # each chat call are snapshotted for assertions.
  class ScriptedClient
    attr_reader :calls, :model, :provider

    def initialize(responses, model: "scripted-model", provider: "scripted")
      @responses = responses
      @calls     = []
      @model     = model
      @provider  = provider
    end

    def chat(messages:, tools:, system:)
      @calls << messages.map(&:dup)
      raise "script exhausted" if @responses.empty?

      @responses.shift
    end

    def assistant_tool_message(response)
      { role: "assistant", content: response.text.presence,
        tool_calls: response.tool_calls.map(&:name) }
    end

    def tool_result_message(tool_call, content, error: false)
      { role: "tool", name: tool_call.name, content: content, error: error }
    end
  end

  def make_turn(text)
    conversation.turns.create!(
      position: Turn.next_position_for(conversation), input_kind: :chat, input_text: text
    )
  end

  def make_pending_event(turn, prompt)
    Event.create_with_position!(
      conversation:, turn:, kind: :ai,
      payload: { "status" => "pending", "blocks" => [], "prompt" => prompt }
    )
  end

  def response(text: "", tool_calls: [], input: 10, output: 5, stop: :stop)
    Ai::Wire::Response.new(
      text:, tool_calls:, stop_reason: stop,
      usage: Ai::Wire::Usage.new(input_tokens: input, output_tokens: output)
    )
  end

  def tool_call(name, arguments = {})
    Ai::Wire::ToolCall.new(id: "tc-#{name}", name:, arguments:)
  end

  def run_with(responses)
    client = ScriptedClient.new(responses)
    allow(Ai::Client).to receive(:current).and_return(client)
    turn  = make_turn("ai test question")
    event = make_pending_event(turn, "test question")
    described_class.perform_now(turn.id)
    [ event.reload, client, turn ]
  end

  describe ".pending?" do
    it "matches only an :ai event still awaiting fill" do
      turn  = make_turn("ai x")
      event = make_pending_event(turn, "x")
      expect(described_class.pending?(event)).to be(true)

      event.update!(payload: event.payload.merge("status" => "done"))
      expect(described_class.pending?(event)).to be(false)
    end
  end

  describe "Flow B — pito_respond" do
    it "finalizes the :ai event with the model's blocks" do
      event, = run_with([
        response(tool_calls: [ tool_call(Ai::Toolset::RESPOND,
          "blocks" => [ { "type" => "text", "text" => "Play Tekken 7." } ]) ])
      ])

      expect(event.kind).to eq("ai")
      expect(event.payload["status"]).to eq("done")
      expect(event.payload["blocks"]).to eq([ { "type" => "text", "text" => "Play Tekken 7." } ])
    end

    it "stamps the answering model into the payload (the message's ✨ badge)" do
      event, = run_with([
        response(tool_calls: [ tool_call(Ai::Toolset::RESPOND,
          "blocks" => [ { "type" => "text", "text" => "hi" } ]) ])
      ])

      expect(event.payload["model"]).to eq("scripted-model")
    end

    it "keeps prose sent alongside pito_respond as a leading text block" do
      event, = run_with([
        response(text: "Here you go.", tool_calls: [ tool_call(Ai::Toolset::RESPOND,
          "blocks" => [ { "type" => "score", "value" => 84 } ]) ])
      ])

      expect(event.payload["blocks"].first).to eq({ "type" => "text", "text" => "Here you go." })
      expect(event.payload["blocks"].last["type"]).to eq("score")
    end
  end

  describe "bare-text stop" do
    it "wraps plain text into a single text block" do
      event, = run_with([ response(text: "Hello there.") ])

      expect(event.payload["blocks"]).to eq([ { "type" => "text", "text" => "Hello there." } ])
      expect(event.payload["status"]).to eq("done")
    end
  end

  describe "Flow A — pito_render_command" do
    it "converts the pending :ai event into the command's native message" do
      event, = run_with([
        response(tool_calls: [ tool_call(Ai::Toolset::RENDER_COMMAND, "command" => "list games") ])
      ])

      expect(event.kind).to eq("system")
      expect(event.payload["prompt"]).to be_nil
    end

    it "keeps prose as the :ai message and appends the command's output after it" do
      event, _client, turn = run_with([
        response(text: "Check your library:", tool_calls: [
          tool_call(Ai::Toolset::RENDER_COMMAND, "command" => "list games")
        ])
      ])

      expect(event.kind).to eq("ai")
      expect(event.payload["blocks"]).to eq([ { "type" => "text", "text" => "Check your library:" } ])
      expect(turn.events.reload.map(&:kind)).to include("system")
    end

    it "feeds an unparseable command back to the model and accepts its retry" do
      event, client, = run_with([
        response(tool_calls: [ tool_call(Ai::Toolset::RENDER_COMMAND, "command" => "frobnicate the vibes") ]),
        response(tool_calls: [ tool_call(Ai::Toolset::RESPOND,
          "blocks" => [ { "type" => "text", "text" => "Recovered." } ]) ])
      ])

      expect(client.calls.size).to eq(2)
      failure = client.calls.last.last
      expect(failure[:error]).to be(true)
      expect(failure[:content]).to include("not a runnable pito command")
      expect(event.payload["blocks"]).to eq([ { "type" => "text", "text" => "Recovered." } ])
    end
  end

  describe "read-tool loop" do
    it "executes reads through the real executor and hands markdown back" do
      event, client, = run_with([
        response(tool_calls: [ tool_call("pito_list", "noun" => "games") ], stop: :tool_use),
        response(text: "You own no games yet.")
      ])

      expect(client.calls.size).to eq(2)
      tool_result = client.calls.last.last
      expect(tool_result[:role]).to eq("tool")
      expect(tool_result[:name]).to eq("pito_list")
      expect(event.payload["blocks"].first["text"]).to eq("You own no games yet.")
    end
  end

  describe "caps" do
    it "finalizes with the capped copy when iterations run out" do
      stub_const("AiOrchestratorJob::MAX_ITERATIONS", 2)
      event, = run_with([
        response(tool_calls: [ tool_call("pito_list", "noun" => "games") ], stop: :tool_use),
        response(tool_calls: [ tool_call("pito_list", "noun" => "vids") ], stop: :tool_use)
      ])

      expect(event.payload["blocks"].first["text"]).to include("exploration limit")
    end

    it "stops the loop once the token budget is spent" do
      stub_const("AiOrchestratorJob::TOKEN_BUDGET", 10)
      event, client, = run_with([
        response(tool_calls: [ tool_call("pito_list", "noun" => "games") ], stop: :tool_use, input: 900, output: 100)
      ])

      expect(client.calls.size).to eq(1)
      expect(event.payload["blocks"].first["text"]).to include("exploration limit")
    end
  end

  describe "failures" do
    it "converts the event to a not-configured error when no client resolves" do
      allow(Ai::Client).to receive(:current).and_raise(Ai::Client::NotConfigured, "no model")
      turn  = make_turn("ai x")
      event = make_pending_event(turn, "x")

      described_class.perform_now(turn.id)

      expect(event.reload.kind).to eq("error")
      expect(event.payload["text"]).to include("/config ai")
    end

    it "converts the event to a failed error on a wire failure" do
      client = ScriptedClient.new([])
      allow(Ai::Client).to receive(:current).and_return(client)
      allow(client).to receive(:chat).and_raise(Ai::Wire::Error.new("boom", status: 500))
      turn  = make_turn("ai x")
      event = make_pending_event(turn, "x")

      described_class.perform_now(turn.id)

      expect(event.reload.kind).to eq("error")
      expect(event.payload["detail"]).to include("boom")
    end

    it "no-ops when the turn carries no pending :ai event" do
      turn = make_turn("list games")
      expect { described_class.perform_now(turn.id) }.not_to raise_error
    end
  end

  describe "history threading" do
    it "sends the prompt as the final user message" do
      _, client, = run_with([ response(text: "ok") ])

      expect(client.calls.first.last).to eq({ role: "user", content: "test question" })
    end
  end
end
