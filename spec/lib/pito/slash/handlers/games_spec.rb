# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Games, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(args: [], raw: nil)
    raw ||= "/games #{args.join(' ')}".strip
    invocation = Pito::Slash::Invocation.new(
      tool:   :games,
      args:   args,
      kwargs: {},
      raw:    raw
    )
    described_class.new(invocation:, conversation:)
  end

  # ── registration ─────────────────────────────────────────────────────────────

  it "is registered in the slash registry" do
    expect(Pito::Slash::Registry.lookup(:games)).to eq(described_class)
  end

  it "has verb :games" do
    expect(described_class.tool).to eq(:games)
  end

  # ── /games (bare) ───────────────────────────────────────────────────────────

  describe "#call — bare /games (no args)" do
    subject(:result) { build_handler(args: []).call }

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns a system event with a witty usage hint" do
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      payload = event[:payload]
      text = payload[:text] || payload["text"]
      expect(text).to be_present
      expect(text.downcase).to include("/games import")
    end
  end

  # ── /games import (no title) ─────────────────────────────────────────────────

  describe "#call — /games import (no title)" do
    subject(:result) { build_handler(args: %w[import]).call }

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns a system event with sidebar_open: 'games_import'" do
      event = result.events.first
      payload = event[:payload]
      expect(payload[:sidebar_open] || payload["sidebar_open"]).to eq("games_import")
    end

    it "sets prefill to empty string when no title given" do
      event = result.events.first
      payload = event[:payload]
      prefill = payload[:prefill] || payload["prefill"]
      expect(prefill.to_s).to be_empty
    end
  end

  # ── /games import Hollow Knight ─────────────────────────────────────────────

  describe "#call — /games import Hollow Knight" do
    subject(:result) do
      build_handler(
        args: %w[import Hollow Knight],
        raw:  "/games import Hollow Knight"
      ).call
    end

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "sets prefill to the title" do
      event = result.events.first
      payload = event[:payload]
      prefill = payload[:prefill] || payload["prefill"]
      expect(prefill).to eq("Hollow Knight")
    end
  end

  # ── /games <unknown> ─────────────────────────────────────────────────────────

  describe "#call — /games unknown_subcommand" do
    subject(:result) { build_handler(args: %w[frobnicate]).call }

    it "returns Result::Ok (witty usage)" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns a usage hint mentioning /games import" do
      event = result.events.first
      payload = event[:payload]
      text = payload[:text] || payload["text"]
      expect(text.downcase).to include("/games import")
    end
  end

  # ── /games --help ────────────────────────────────────────────────────────────

  describe "#call — /games --help" do
    subject(:result) do
      invocation = Pito::Slash::Invocation.new(
        tool:   :games,
        args:   [],
        kwargs: {},
        raw:    "/games --help"
      )
      described_class.new(invocation:, conversation:).call
    end

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns a man-page help block with Usage: and import subcommand" do
      payload = result.events.first[:payload]
      expect(payload["html"]).to be true
      body = payload["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("Usage:")
      expect(body.downcase).to include("import")
    end
  end
end
