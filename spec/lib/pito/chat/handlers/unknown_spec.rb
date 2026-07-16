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
          input: "list vids", conversation: conversation, channel: nil, period: nil, viewport_width: nil
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
