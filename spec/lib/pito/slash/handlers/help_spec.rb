# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Help, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(authenticated: true)
    invocation = Pito::Slash::Invocation.new(tool: :help, args: [], kwargs: {}, raw: "/help")
    described_class.new(invocation:, conversation:, authenticated:)
  end

  describe "#call — authenticated" do
    it "returns a Result::Ok with one event" do
      expect(build_handler.call).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns exactly 1 event" do
      result = build_handler.call
      expect(result.events.size).to eq(1)
    end

    it "event is system with a body payload" do
      event = build_handler.call.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload][:body]).to be_present
    end

    it "includes sections with commands and keybindings" do
      payload = build_handler.call.events.first[:payload]
      expect(payload[:sections]).to be_an(Array)
      titles = payload[:sections].map { |s| s[:title] }
      expect(titles).to include("COMMANDS")
      expect(titles).to include("KEYBINDINGS")
    end

    it "sets expand/collapse labels" do
      payload = build_handler.call.events.first[:payload]
      expect(payload[:expand_label]).to be_present
      expect(payload[:collapse_label]).to be_present
    end
  end

  describe "#call — unauthenticated" do
    it "returns a Result::Ok" do
      expect(build_handler(authenticated: false).call).to be_a(Pito::Slash::Result::Ok)
    end

    it "shows the authentication instruction" do
      event = build_handler(authenticated: false).call.events.first
      expect(event[:payload][:message_key]).to eq("pito.slash.help.unauthenticated")
    end

    it "does not include sections" do
      event = build_handler(authenticated: false).call.events.first
      expect(event[:payload][:sections]).to be_nil
    end
  end

  # ── /help --help (nonsense man-page, via HelpBuilder) ───────────────────────
  # The dispatcher intercepts --help before the handler runs; we test
  # HelpBuilder directly here to verify the nonsense man page is rendered.

  describe "/help --help (nonsense man-page via HelpBuilder)" do
    def build_help_invocation
      Pito::Slash::Invocation.new(tool: :help, args: [], kwargs: {}, raw: "/help --help")
    end

    subject(:result) do
      Pito::Slash::HelpBuilder.call(invocation: build_help_invocation)
    end

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "renders exactly 1 system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload has html: true and a body" do
      payload = result.events.first[:payload]
      expect(payload["html"]).to be true
      expect(payload["body"]).to be_present
    end

    it "body contains .pito-help-block" do
      expect(result.events.first[:payload]["body"]).to include("pito-help-block")
    end

    it "body includes the nonsense title (manual's manual)" do
      expect(result.events.first[:payload]["body"]).to include("manual")
    end

    it "body includes expected nonsense rows" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("uninstall reality")
      expect(body).to include("touch grass")
      expect(body).to include("brain.cells")
    end
  end
end
