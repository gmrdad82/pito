# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Notifications, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(args: [], raw: nil)
    raw ||= "/notifications #{args.join(' ')}".strip
    invocation = Pito::Slash::Invocation.new(
      verb:   :notifications,
      args:   args,
      kwargs: {},
      raw:    raw
    )
    described_class.new(invocation:, conversation:)
  end

  # Stub the cable broadcast so tests don't require a full cable stack.
  before do
    allow_any_instance_of(Pito::Stream::Broadcaster)
      .to receive(:broadcast_notifications_sidebar)
  end

  # ── /notifications (bare) — opens sidebar ───────────────────────────────────

  describe "#call — bare /notifications (no args)" do
    it "returns Result::Ok" do
      expect(build_handler(args: []).call).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns a system event with sidebar_open: 'notifications'" do
      result = build_handler(args: []).call
      expect(result.events.first[:payload][:sidebar_open]).to eq("notifications")
    end

    it "includes a non-blank opening text" do
      result = build_handler(args: []).call
      expect(result.events.first[:payload][:text]).to be_present
    end

    it "calls broadcast_notifications_sidebar on the broadcaster" do
      broadcaster = instance_double(Pito::Stream::Broadcaster)
      allow(broadcaster).to receive(:broadcast_notifications_sidebar)
      allow(Pito::Stream::Broadcaster).to receive(:new).with(conversation:).and_return(broadcaster)

      build_handler(args: []).call

      expect(broadcaster).to have_received(:broadcast_notifications_sidebar)
    end
  end

  # ── /notifications (with extra tokens) — still opens sidebar ────────────────

  describe "#call — /notifications with extra tokens" do
    it "ignores extra tokens and opens sidebar" do
      result = build_handler(args: %w[whatever]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:sidebar_open]).to eq("notifications")
    end

    it "ignores multiple extra tokens and opens sidebar" do
      result = build_handler(args: %w[foo bar]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:sidebar_open]).to eq("notifications")
    end
  end

  # ── Grammar spec ──────────────────────────────────────────────────────────────

  describe "grammar spec" do
    before { Pito::Grammar::Registry.reset!; Pito::Grammar::Registry.register_all! }
    after  { Pito::Grammar::Registry.reset! }

    it "is registered under :slash namespace" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :notifications)
      expect(spec).not_to be_nil
    end

    it "has auth :authenticated_only" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :notifications)
      expect(spec.auth).to eq(:authenticated_only)
    end

    it "has no positional slots" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :notifications)
      positional = spec.slots.reject { |s| s.kind == :kv || s.kind == :connective }
      expect(positional).to be_empty
    end
  end

  # ── Autosuggest (auth-filtered) ───────────────────────────────────────────────

  describe "autosuggest filtering" do
    before { Pito::Grammar::Registry.reset!; Pito::Grammar::Registry.register_all! }
    after  { Pito::Grammar::Registry.reset! }

    it "appears in authenticated slash suggestions" do
      names = Pito::Suggestions::Catalog.to_h(authenticated: true)[:slash].map { |e| e[:name] }
      expect(names).to include("notifications")
    end

    it "does NOT appear in unauthenticated slash suggestions" do
      names = Pito::Suggestions::Catalog.to_h(authenticated: false)[:slash].map { |e| e[:name] }
      expect(names).not_to include("notifications")
    end
  end

  # ── /notifications --help — man-style via HelpBuilder ─────────────────────────
  # --help is intercepted by the dispatcher before the handler runs.
  # Test via HelpBuilder.call directly, mirroring help_builder_spec.rb patterns.

  describe "/notifications --help (via HelpBuilder)" do
    def build_invocation(raw:)
      verb = raw.strip.split(/\s+/).first.delete_prefix("/").to_sym
      Pito::Slash::Invocation.new(verb:, args: [], kwargs: {}, raw:)
    end

    subject(:result) do
      Pito::Slash::HelpBuilder.call(invocation: build_invocation(raw: "/notifications --help"))
    end

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns exactly 1 system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq("system")
    end

    it "payload has html: true" do
      expect(result.events.first[:payload]["html"]).to be true
    end

    it "body contains .pito-help-block" do
      expect(result.events.first[:payload]["body"]).to include("pito-help-block")
    end

    it "body contains Usage:" do
      expect(result.events.first[:payload]["body"]).to include("Usage:")
    end

    it "body contains /notifications" do
      expect(result.events.first[:payload]["body"]).to include("/notifications")
    end
  end
end
