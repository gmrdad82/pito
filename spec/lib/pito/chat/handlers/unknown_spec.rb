# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Unknown do
  subject(:handler) do
    described_class.new(
      message: Pito::Chat::Message.new(tool: nil, body_tokens: [], kind: :unknown, raw: "boo!"),
      conversation: Conversation.singleton
    )
  end

  describe "#call" do
    it "returns a Result::Ok — unparseable input gets a witty reply, not an error" do
      expect(handler.call).to be_a(Pito::Chat::Result::Ok)
    end

    it "emits a single :system event with non-empty text" do
      result = handler.call
      expect(result.events.length).to eq(1)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload][:text]).to be_present
    end

    it "always nudges toward help" do
      expect(handler.call.events.first[:payload][:text].downcase).to include("help")
    end
  end

  # ── NL gate (3.0.0, see lib/pito/chat/handlers/unknown.rb's header for the
  # full dated policy) ─────────────────────────────────────────────────────
  #
  # Pito::Nl::Router and Pito::Nl::Mapper are stubbed at the module level
  # throughout — never the sidecars underneath (Embedding::Client /
  # CompletionClient) — same idiom as spec/lib/pito/nl/mapper_spec.rb's own
  # CompletionClient stub, one level up the call chain since this gate is
  # what actually consumes both Router and Mapper.
  describe "the NL gate" do
    let(:conversation)       { Conversation.singleton }
    let(:auto_run_threshold) { Pito::Dispatch::Config.nl_thresholds[:auto_run] }
    let(:suggest_threshold)  { Pito::Dispatch::Config.nl_thresholds[:suggest] }

    def build_handler(raw:)
      described_class.new(
        message: Pito::Chat::Message.new(tool: nil, body_tokens: [], kind: :unknown, raw: raw),
        conversation: conversation
      )
    end

    def route(tool:, confidence:)
      { tool: tool, confidence: confidence, nearest_phrase: "some phrase" }
    end

    context "when the router returns nil (below suggest, NL routing off, or sidecar down)" do
      it "falls back to the huh copy without ever consulting the mapper" do
        allow(Pito::Nl::Router).to receive(:route).and_return(nil)
        expect(Pito::Nl::Mapper).not_to receive(:map)

        result = build_handler(raw: "what's the weather like").call

        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.length).to eq(1)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "when the router hits but the mapper returns nil" do
      it "falls back to the huh copy" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :list, confidence: auto_run_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("show my vids").and_return(nil)

        result = build_handler(raw: "show my vids").call

        expect(result.events.length).to eq(1)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "agreement, confidence >= auto_run, and the mapped tool is read-only" do
      it "executes through the real dispatch path with the canonicalized command, attributed" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :list, confidence: auto_run_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("show my vids").and_return(command: "ls vids", tool: :list)
        dispatched = Pito::Chat::Result::Ok.new(events: [ { kind: :list, payload: { rows: [] } } ])
        allow(Pito::Dispatch::Router).to receive(:call).and_return(dispatched)

        result = build_handler(raw: "show my vids").call

        expect(Pito::Dispatch::Router).to have_received(:call).with(
          input: "list vids", conversation: conversation, channel: nil, period: nil, viewport_width: nil,
          nl_retry: true # the P7 loop guard: a mapped command never re-enters the gate
        )
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.length).to eq(2)
        expect(result.events.first).to eq(
          kind: :system,
          payload: { text: Pito::Copy.render("pito.copy.nl.ran", command: "list vids") }
        )
        expect(result.events.last).to eq(kind: :list, payload: { rows: [] })
      end
    end

    # ── The read-only declaration (3.0.1 P13) ─────────────────────────────────
    # :list above exercises the mcp.read_only FALLBACK (list declares no
    # tool-level key). The pure-read chat tools (analyze, at-a-glance,
    # breakdowns, channels, linked, search, help) declare tool-level
    # `read_only: true` while their mcp.read_only is false (the strict MCP
    # readOnlyHint counts cache warming / external API calls) — pre-P13 the
    # gate read only the mcp flag, so they could NEVER auto-run.
    context "agreement at auto_run confidence on a tool-level read_only tool (analyze — mcp.read_only false)" do
      it "auto-runs: the tool-level declaration wins over the mcp flag" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :analyze, confidence: auto_run_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("how are my views doing?")
                                                 .and_return(command: "stats", tool: :analyze)
        dispatched = Pito::Chat::Result::Ok.new(events: [ { kind: :enhanced, payload: { text: "numbers" } } ])
        allow(Pito::Dispatch::Router).to receive(:call).and_return(dispatched)

        result = build_handler(raw: "how are my views doing?").call

        expect(Pito::Dispatch::Router).to have_received(:call)
          .with(hash_including(input: "analyze", nl_retry: true))
        expect(result.events.length).to eq(2)
        expect(result.events.first).to eq(
          kind: :system,
          payload: { text: Pito::Copy.render("pito.copy.nl.ran", command: "analyze") }
        )
      end
    end

    context "an explicit tool-level read_only: false, even with mcp.read_only true underneath" do
      it "never auto-runs — the tool-level declaration is authoritative, not a mere default" do
        allow(Pito::Dispatch::Config).to receive(:tool).and_call_original
        allow(Pito::Dispatch::Config).to receive(:tool).with(:list)
          .and_return({ read_only: false, mcp: { read_only: true } })
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :list, confidence: auto_run_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("show my vids").and_return(command: "ls vids", tool: :list)
        allow(Pito::Dispatch::Router).to receive(:call)

        result = build_handler(raw: "show my vids").call

        expect(Pito::Dispatch::Router).not_to have_received(:call)
        expect(result.events.first[:kind]).to eq(:confirmation)
        expect(result.events.first[:payload]["nl_command"]).to eq("list vids")
      end
    end

    context "agreement, confidence in [suggest, auto_run)" do
      it "emits a did-you-mean confirmation carrying the nl_run payload" do
        mid_confidence = (auto_run_threshold + suggest_threshold) / 2.0
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :list, confidence: mid_confidence))
        allow(Pito::Nl::Mapper).to receive(:map).with("show my vids").and_return(command: "ls vids", tool: :list)
        allow(Pito::Dispatch::Router).to receive(:call)

        result = build_handler(raw: "show my vids").call

        expect(Pito::Dispatch::Router).not_to have_received(:call)
        expect(result.events.length).to eq(1)
        event = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("nl_run")
        expect(event[:payload]["nl_command"]).to eq("list vids")
        expect(event[:payload]["conversation_id"]).to eq(conversation.id)
      end
    end

    # ── Loop guard (3.0.1 P7): a mapped command that itself soft-fails ────────
    # run_now dispatches with nl_retry: true, so the nested Router returns the
    # nl_fallback marker instead of re-entering the gate; run_now degrades it
    # to the step-6 did-you-mean copy — never a recursive gate pass.
    context "auto-run whose mapped command itself soft-fails (nl_fallback marker returned)" do
      it "degrades to the did-you-mean confirmation for the mapped command, never recursing" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :show, confidence: auto_run_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("show me my tekken vids")
                                                 .and_return(command: "show vids tekken", tool: :show)
        marker = Pito::Chat::Result::Error.new(
          message_key: "pito.copy.videos.not_found", message_args: { ref: "tekken" }, nl_fallback: true
        )
        allow(Pito::Dispatch::Router).to receive(:call).and_return(marker)

        result = build_handler(raw: "show me my tekken vids").call

        expect(Pito::Dispatch::Router).to have_received(:call)
          .with(hash_including(input: "show vids tekken", nl_retry: true)).once
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["nl_command"]).to eq("show vids tekken")
      end
    end

    context "a write-capable tool, at ANY confidence" do
      it "never auto-runs — always falls to did-you-mean" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :delete, confidence: 0.999))
        allow(Pito::Nl::Mapper).to receive(:map).with("get rid of that game")
                                                 .and_return(command: "rm games", tool: :delete)
        allow(Pito::Dispatch::Router).to receive(:call)

        result = build_handler(raw: "get rid of that game").call

        expect(Pito::Dispatch::Router).not_to have_received(:call)
        event = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["nl_command"]).to eq("delete games")
      end
    end

    # ── The field-scoped write exception (OWNER DIRECTIVE Q17, 3.8.0) ─────────
    # `update` is a write tool (never read-only auto-runnable), but tools.yml
    # declares `nl_auto_run_fields: [footage]` on it: a mapped update command
    # whose FIELD token is footage auto-runs (footage is local-only and
    # reversible); every other update field keeps the confirm-first
    # did-you-mean. See Unknown#auto_run_field? + the tools.yml key comment.
    context "update+footage at auto_run confidence (the nl_auto_run_fields exception)" do
      it "auto-runs the mapped footage command through the real dispatch path, attributed" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :update, confidence: auto_run_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("log two more hours on game 8")
                                                 .and_return(command: "update game footage 8 +2", tool: :update)
        dispatched = Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: { "text" => "done" } } ])
        allow(Pito::Dispatch::Router).to receive(:call).and_return(dispatched)

        result = build_handler(raw: "log two more hours on game 8").call

        expect(Pito::Dispatch::Router).to have_received(:call)
          .with(hash_including(input: "update game footage 8 +2", nl_retry: true))
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first).to eq(
          kind: :system,
          payload: { text: Pito::Copy.render("pito.copy.nl.ran", command: "update game footage 8 +2") }
        )
      end
    end

    context "update+description at the SAME auto_run confidence (the exception is field-aware)" do
      it "still confirm-gates — a description update never auto-runs" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :update, confidence: auto_run_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("rewrite vid 7's description")
                                                 .and_return(command: "update vid description 7 fresh words", tool: :update)
        allow(Pito::Dispatch::Router).to receive(:call)

        result = build_handler(raw: "rewrite vid 7's description").call

        expect(Pito::Dispatch::Router).not_to have_received(:call)
        event = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["nl_command"]).to eq("update vid description 7 fresh words")
      end

      it "is not fooled by the word 'footage' inside the VALUE — only the field token counts" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :update, confidence: auto_run_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("describe vid 7 as a footage recap")
                                                 .and_return(command: "update vid description 7 footage recap", tool: :update)
        allow(Pito::Dispatch::Router).to receive(:call)

        result = build_handler(raw: "describe vid 7 as a footage recap").call

        expect(Pito::Dispatch::Router).not_to have_received(:call)
        expect(result.events.first[:kind]).to eq(:confirmation)
      end
    end

    context "mismatch re-try (router and mapper disagree on the tool)" do
      context "when the constrained retry resolves to the router's own tool" do
        it "replaces the mismatched mapping, so the retried command runs the normal branches" do
          allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :list, confidence: auto_run_threshold))
          allow(Pito::Nl::Mapper).to receive(:map).with("what rpgs do i have")
                                                   .and_return(command: "rm games", tool: :delete)
          allow(Pito::Nl::Mapper).to receive(:map).with("what rpgs do i have", tool: :list)
                                                   .and_return(command: "ls games", tool: :list)
          dispatched = Pito::Chat::Result::Ok.new(events: [])
          allow(Pito::Dispatch::Router).to receive(:call).and_return(dispatched)

          build_handler(raw: "what rpgs do i have").call

          expect(Pito::Nl::Mapper).to have_received(:map).with("what rpgs do i have").once
          expect(Pito::Nl::Mapper).to have_received(:map).with("what rpgs do i have", tool: :list).once
          expect(Pito::Dispatch::Router).to have_received(:call).with(hash_including(input: "list games"))
        end
      end

      context "when the constrained retry can't resolve (nil)" do
        it "falls back to did-you-mean with the canonicalized ORIGINAL (mismatched) command" do
          allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :list, confidence: auto_run_threshold))
          allow(Pito::Nl::Mapper).to receive(:map).with("what rpgs do i have")
                                                   .and_return(command: "rm games", tool: :delete)
          allow(Pito::Nl::Mapper).to receive(:map).with("what rpgs do i have", tool: :list).and_return(nil)
          allow(Pito::Dispatch::Router).to receive(:call)

          result = build_handler(raw: "what rpgs do i have").call

          expect(Pito::Nl::Mapper).to have_received(:map).with("what rpgs do i have", tool: :list).once
          expect(Pito::Dispatch::Router).not_to have_received(:call)
          event = result.events.first
          expect(event[:kind]).to eq(:confirmation)
          expect(event[:payload]["nl_command"]).to eq("delete games")
        end
      end
    end

    context "canonicalization" do
      it "displays and would execute an alias-led mapper command under its canonical tool name" do
        allow(Pito::Nl::Router).to receive(:route).and_return(route(tool: :delete, confidence: suggest_threshold))
        allow(Pito::Nl::Mapper).to receive(:map).with("get rid of that game")
                                                 .and_return(command: "rm games", tool: :delete)

        result = build_handler(raw: "get rid of that game").call

        event = result.events.first
        expect(event[:payload]["nl_command"]).to eq("delete games")
        expect(event[:payload]["body"]).to include("delete games")
        expect(event[:payload]["body"]).not_to include("rm games")
      end
    end
  end
end
