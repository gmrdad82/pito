# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Theme, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(args: [], raw: nil)
    raw ||= "/themes #{args.join(' ')}".strip
    invocation = Pito::Slash::Invocation.new(
      verb:   :themes,
      args:   args,
      kwargs: {},
      raw:    raw
    )
    described_class.new(invocation:, conversation:)
  end

  # ── /themes (bare) — opens sidebar ──────────────────────────────────────────

  describe "#call — bare /themes (no args)" do
    it "returns Result::Ok" do
      expect(build_handler(args: []).call).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns a system event with sidebar_open: 'theme'" do
      result = build_handler(args: []).call
      expect(result.events.first[:payload][:sidebar_open]).to eq("theme")
    end
  end

  # ── /themes (with extra tokens) — still opens sidebar ───────────────────────

  describe "#call — /themes with extra tokens" do
    it "ignores extra tokens and opens sidebar" do
      result = build_handler(args: %w[whatever]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:sidebar_open]).to eq("theme")
    end

    it "ignores multiple extra tokens and opens sidebar" do
      result = build_handler(args: %w[foo bar baz]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:sidebar_open]).to eq("theme")
    end
  end

  # NOTE: `/themes --help` is intercepted by the universal slash --help handler
  # (Pito::Slash::HelpRenderer) BEFORE this handler runs, so it never reaches
  # #call. That routing (→ the "manual's manual" easter egg) is covered in
  # spec/lib/pito/slash/help_renderer_spec.rb.

  # ── Grammar spec ─────────────────────────────────────────────────────────────

  describe "grammar spec" do
    before { Pito::Grammar::Registry.reset!; Pito::Grammar::Registry.register_all! }
    after  { Pito::Grammar::Registry.reset! }

    it "is registered under :slash namespace" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :themes)
      expect(spec).not_to be_nil
    end

    it "has auth :authenticated_only" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :themes)
      expect(spec.auth).to eq(:authenticated_only)
    end

    it "has no positional slots" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :themes)
      positional = spec.slots.reject { |s| s.kind == :kv || s.kind == :connective }
      expect(positional).to be_empty
    end
  end

  # ── Registry.resolve_target (not used by handler, but used by Sidebar) ───────

  describe "Pito::Themes::Registry.resolve_target" do
    it "returns a Definition for a known slug" do
      defn = Pito::Themes::Registry.resolve_target("dracula")
      expect(defn).not_to be_nil
      expect(defn.slug).to eq("dracula")
    end

    it "resolves 'default' to the tokyo-night Definition" do
      defn = Pito::Themes::Registry.resolve_target("default")
      expect(defn).not_to be_nil
      expect(defn.slug).to eq("tokyo-night")
    end

    it "returns nil for an unknown token" do
      expect(Pito::Themes::Registry.resolve_target("nope-not-a-theme")).to be_nil
    end
  end

  # ── Broadcaster.broadcast_global_theme ──────────────────────────────────────

  describe "Pito::Stream::Broadcaster.broadcast_global_theme" do
    include ActionCable::TestHelper

    it "broadcasts a set-theme action to pito:global" do
      expect {
        Pito::Stream::Broadcaster.broadcast_global_theme("nord")
      }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("set-theme")
        expect(content).to include("nord")
      }
    end
  end
end
