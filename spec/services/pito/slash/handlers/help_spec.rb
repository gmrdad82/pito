# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Help, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(authenticated: true)
    invocation = Pito::Slash::Invocation.new(verb: :help, args: [], kwargs: {}, raw: "/help")
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
      expect(event[:kind]).to eq("system")
      expect(event[:payload][:body]).to be_present
    end

    it "includes sections with commands" do
      payload = build_handler.call.events.first[:payload]
      expect(payload[:sections]).to be_an(Array)
      titles = payload[:sections].map { |s| s[:title] }
      expect(titles).to include("GENERAL")
      expect(titles).to include("YOUTUBE")
      expect(titles).to include("CONFIG")
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

    it "does not include sections or expand_lines" do
      event = build_handler(authenticated: false).call.events.first
      expect(event[:payload][:sections]).to be_nil
      expect(event[:payload][:expand_lines]).to be_nil
    end
  end

  # ── P56 — /help --help (nonsense dictionary, via HelpRenderer) ──────────────
  # The dispatcher intercepts --help before the handler runs; we test the
  # HelpRenderer directly here to verify the nonsense table is rendered.

  describe "P56 /help --help (nonsense kv-table via HelpRenderer)" do
    def build_help_invocation
      Pito::Slash::Invocation.new(verb: :help, args: [], kwargs: {}, raw: "/help --help")
    end

    subject(:result) do
      Pito::Slash::HelpRenderer.call(invocation: build_help_invocation, authenticated: true)
    end

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "renders exactly 1 system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq("system")
    end

    it "includes 10 nonsense table_rows" do
      rows = result.events.first[:payload][:table_rows]
      expect(rows.size).to eq(10)
    end

    it "table_rows include expected nonsense keys" do
      keys = result.events.first[:payload][:table_rows].map { |r| r[:key] }
      expect(keys).to include("/uninstall reality", "--help --help", "set brain.cells=∞")
    end

    it "body is the nonsense title" do
      body = result.events.first[:payload][:body]
      expect(body).to be_present
      expect(body).to include("manual")
    end
  end
end
