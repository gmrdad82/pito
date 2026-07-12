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
    attr_reader :calls, :model, :provider, :effort

    def initialize(responses, model: "scripted-model", provider: "scripted", effort: nil)
      @responses = responses
      @calls     = []
      @model     = model
      @provider  = provider
      @effort    = effort
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

  def response(text: "", tool_calls: [], input: 10, output: 5, stop: :stop, cost: nil)
    Ai::Wire::Response.new(
      text:, tool_calls:, stop_reason: stop,
      usage: Ai::Wire::Usage.new(input_tokens: input, output_tokens: output, cost: cost)
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

  describe "web opt-in system prompt (smoke-found)" do
    it "appends the explicit WEB availability line only on --web turns" do
      job = described_class.new
      turn  = make_turn("@ai --web q")
      event = make_pending_event(turn, "q")
      event.update!(payload: event.payload.merge("web" => true))
      job.instance_variable_set(:@event, event)
      expect(job.send(:run_system_prompt)).to include("web_search and web_fetch tools ARE available")

      event.update!(payload: event.payload.except("web"))
      expect(job.send(:run_system_prompt)).not_to include("ARE available")
    end
  end

  describe "status line (T16.29: copy-only, gerund-led)" do
    it "renders exactly one dictionary variant — no label prefix, no tool id" do
      line = described_class.new.send(:status_line, "pito_list", { "noun" => "vids" })
      variants = I18n.t("pito.copy.ai.status.pito_list")
      expect(Array(variants)).to include(line)
      expect(line).not_to include(":")
      expect(line).not_to include("pito_list")
    end

    it "falls to the tool-nameless generic dictionary for unknown tools" do
      line = described_class.new.send(:status_line, "mcp_custom_thing", {})
      expect(Array(I18n.t("pito.copy.ai.status.generic"))).to include(line)
      expect(line).not_to include("mcp_custom_thing")
    end
  end

  describe "streaming (P13)" do
    # A client that DECLARES streaming and yields pito_respond argument
    # fragments before returning the assembled response — the wire contract.
    class StreamingScriptedClient < ScriptedClient
      def initialize(responses, fragments:, **kwargs)
        super(responses, **kwargs)
        @fragments = fragments
      end

      def streaming? = true

      def chat(messages:, tools:, system:)
        @fragments.each { |frag| yield(Ai::Toolset::RESPOND, frag) } if block_given?
        super
      end
    end

    it "broadcasts each block as it closes mid-stream, then finalizes from the full payload" do
      payload   = '{"blocks": [{"type": "text", "text": "one"}, {"type": "text", "text": "two"}]}'
      fragments = payload.chars.each_slice(7).map(&:join) # arbitrary split points
      client    = StreamingScriptedClient.new(
        [ response(tool_calls: [ tool_call(Ai::Toolset::RESPOND,
          "blocks" => [ { "type" => "text", "text" => "one" }, { "type" => "text", "text" => "two" } ]) ]) ],
        fragments: fragments
      )
      allow(Ai::Client).to receive(:current).and_return(client)
      expect_any_instance_of(Pito::Stream::Broadcaster)
        .to receive(:broadcast_ai_block).twice.and_return(nil)

      turn  = make_turn("@ai stream test")
      event = make_pending_event(turn, "stream test")
      described_class.perform_now(turn.id)

      expect(event.reload.payload["blocks"].map { |b| b["text"] }).to eq(%w[one two])
    end

    it "previews a kv_table ROW BY ROW via partial snapshots, then its final form, at the same index" do
      kv   = { "type" => "kv_table", "rows" => [ [ "Rating", "84" ], [ "Genre", "RPG" ] ] }
      txt  = { "type" => "text", "text" => "done" }
      json = JSON.generate("blocks" => [ kv, txt ])
      # Deterministic boundaries: fragment 1 ends exactly at the first row's
      # closing bracket, fragment 2 completes the kv block, fragment 3 the rest.
      first_row_end = json.index(']') + 1
      kv_end        = json.index('},') + 1
      fragments     = [ json[0...first_row_end], json[first_row_end...kv_end], json[kv_end..] ]

      client = StreamingScriptedClient.new(
        [ response(tool_calls: [ tool_call(Ai::Toolset::RESPOND, "blocks" => [ kv, txt ]) ]) ],
        fragments: fragments
      )
      allow(Ai::Client).to receive(:current).and_return(client)

      seen = []
      allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:broadcast_ai_block) do |_b, event:, block:, index:|
        seen << [ index, block["type"], block["rows"]&.size ]
      end

      turn  = make_turn("@ai row stream")
      make_pending_event(turn, "row stream")
      described_class.perform_now(turn.id)

      expect(seen).to eq([
        [ 1, "kv_table", 1 ], # partial: first row only, upserted in place…
        [ 1, "kv_table", 2 ], # …then the block's final complete form
        [ 2, "text", nil ]
      ])
    end

    it "never previews a partial for a non-row type (charts land whole)" do
      chart = { "type" => "chart", "viz" => "bar",
                "data" => { "bars" => [ { "label" => "Solo", "pct" => 60.0 }, { "label" => "Co-op", "pct" => 40.0 } ] } }
      json  = JSON.generate("blocks" => [ chart ])
      client = StreamingScriptedClient.new(
        [ response(tool_calls: [ tool_call(Ai::Toolset::RESPOND, "blocks" => [ chart ]) ]) ],
        fragments: json.chars.each_slice(5).map(&:join)
      )
      allow(Ai::Client).to receive(:current).and_return(client)

      seen = []
      allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:broadcast_ai_block) do |_b, event:, block:, index:|
        seen << [ index, block["type"] ]
      end

      turn = make_turn("@ai chart stream")
      make_pending_event(turn, "chart stream")
      described_class.perform_now(turn.id)

      expect(seen).to eq([ [ 1, "chart" ] ])
    end

    it "takes the plain non-streaming call for clients without streaming support" do
      event, = run_with([
        response(tool_calls: [ tool_call(Ai::Toolset::RESPOND,
          "blocks" => [ { "type" => "text", "text" => "plain" } ]) ])
      ])

      expect(event.payload["blocks"].first["text"]).to eq("plain")
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

    it "stamps ONLY the provider-REPORTED cost (T16.22: pito never computes a price)" do
      event, = run_with([
        response(cost: 0.0042, tool_calls: [ tool_call(Ai::Toolset::RESPOND,
          "blocks" => [ { "type" => "text", "text" => "hi" } ]) ])
      ])

      expect(event.payload["cost_amount"]).to eq(0.0042)
      expect(event.payload["cost_currency"]).to eq("USD")
    end

    it "stamps NO cost when the provider reports none — unknown is not free" do
      event, = run_with([
        response(tool_calls: [ tool_call(Ai::Toolset::RESPOND,
          "blocks" => [ { "type" => "text", "text" => "hi" } ]) ])
      ])

      expect(event.payload).not_to have_key("cost_amount")
      expect(event.payload).not_to have_key("cost_currency")
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
