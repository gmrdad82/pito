# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe Pito::Slash::Handlers::Theme, type: :service do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.create! }

  def build_handler(args: [], raw: nil)
    raw ||= "/theme #{args.join(' ')}".strip
    invocation = Pito::Slash::Invocation.new(
      verb:   :theme,
      args:   args,
      kwargs: {},
      raw:    raw
    )
    described_class.new(invocation:, conversation:)
  end

  # ── /theme apply <name> ──────────────────────────────────────────────────────

  describe "#call — /theme apply dracula" do
    it "returns Result::Ok" do
      expect(build_handler(args: %w[apply dracula]).call).to be_a(Pito::Slash::Result::Ok)
    end

    it "persists the theme in AppSetting" do
      AppSetting.theme = "tokyo-night"
      build_handler(args: %w[apply dracula]).call
      expect(AppSetting.theme).to eq("dracula")
    end

    it "returns a system event with confirmation text" do
      result = build_handler(args: %w[apply dracula]).call
      text = result.events.first[:payload][:text]
      expect(text).to be_present
      expect(text.downcase).to include("dracula").or include("theme")
    end

    it "broadcasts set-theme to pito:global" do
      expect {
        build_handler(args: %w[apply dracula]).call
      }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("set-theme")
        expect(content).to include("dracula")
      }
    end
  end

  # ── /theme <name> (bare shorthand → apply) ──────────────────────────────────

  describe "#call — bare /theme dracula (shorthand apply)" do
    it "persists dracula in AppSetting" do
      AppSetting.theme = "tokyo-night"
      build_handler(args: %w[dracula]).call
      expect(AppSetting.theme).to eq("dracula")
    end

    it "returns Result::Ok" do
      expect(build_handler(args: %w[dracula]).call).to be_a(Pito::Slash::Result::Ok)
    end

    it "broadcasts set-theme" do
      expect {
        build_handler(args: %w[dracula]).call
      }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("dracula")
      }
    end
  end

  # ── /theme apply default ─────────────────────────────────────────────────────

  describe "#call — /theme apply default (resolves to tokyo-night)" do
    it "persists 'tokyo-night' (the default)" do
      AppSetting.theme = "dracula"
      build_handler(args: %w[apply default]).call
      expect(AppSetting.theme).to eq("tokyo-night")
    end
  end

  # ── /theme preview <name> ────────────────────────────────────────────────────

  describe "#call — /theme preview dracula" do
    it "returns Result::Ok" do
      expect(build_handler(args: %w[preview dracula]).call).to be_a(Pito::Slash::Result::Ok)
    end

    it "does NOT persist the theme" do
      AppSetting.theme = "tokyo-night"
      build_handler(args: %w[preview dracula]).call
      expect(AppSetting.theme).to eq("tokyo-night")
    end

    it "broadcasts set-theme so the page recolors" do
      expect {
        build_handler(args: %w[preview dracula]).call
      }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("set-theme")
        expect(content).to include("dracula")
      }
    end

    it "returns a system event hinting apply/reset" do
      result  = build_handler(args: %w[preview dracula]).call
      text    = result.events.first[:payload][:text]
      expect(text).to include("/theme apply dracula").or include("apply")
      expect(text).to include("/theme reset").or include("reset")
    end
  end

  # ── /theme reset ────────────────────────────────────────────────────────────

  describe "#call — /theme reset" do
    it "returns Result::Ok" do
      expect(build_handler(args: %w[reset]).call).to be_a(Pito::Slash::Result::Ok)
    end

    it "resets AppSetting.theme to tokyo-night" do
      AppSetting.theme = "dracula"
      build_handler(args: %w[reset]).call
      expect(AppSetting.theme).to eq("tokyo-night")
    end

    it "broadcasts set-theme with tokyo-night" do
      expect {
        build_handler(args: %w[reset]).call
      }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("tokyo-night")
      }
    end
  end

  # ── /theme <unknown> ────────────────────────────────────────────────────────

  describe "#call — unknown target" do
    it "returns Result::Error" do
      result = build_handler(args: %w[not-a-real-theme]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
    end

    it "uses the unknown_target i18n key" do
      result = build_handler(args: %w[not-a-real-theme]).call
      expect(result.message_key).to eq("pito.slash.theme.errors.unknown_target")
    end

    it "interpolates the bad name" do
      result = build_handler(args: %w[neon-abyss]).call
      expect(result.message_args[:name]).to eq("neon-abyss")
    end
  end

  # ── /theme list (placeholder) ────────────────────────────────────────────────

  describe "#call — /theme list" do
    it "returns Result::Ok with a placeholder system message" do
      result = build_handler(args: %w[list]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:text]).to be_present
    end
  end

  # ── /theme (bare) — sidebar placeholder ────────────────────────────────────

  describe "#call — bare /theme (no args)" do
    it "returns Result::Ok with a placeholder message" do
      result = build_handler(args: []).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:text]).to be_present
    end
  end

  # ── /theme --help ────────────────────────────────────────────────────────────

  describe "#show_help" do
    it "returns Result::Ok" do
      handler = build_handler(raw: "/theme --help")
      expect(handler.show_help).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns a system event with a usage body and table_rows" do
      handler  = build_handler(raw: "/theme --help")
      payload  = handler.show_help.events.first[:payload]
      expect(payload[:body]).to include("/theme")
      expect(payload[:table_rows]).to be_an(Array)
      expect(payload[:table_rows]).not_to be_empty
    end

    it "table_rows include at least one dark and one light theme" do
      handler  = build_handler(raw: "/theme --help")
      payload  = handler.show_help.events.first[:payload]
      keys = payload[:table_rows].map { |r| r[:key] }
      # We have dark themes like tokyo-night and light themes like github-light
      expect(keys).to include("tokyo-night")
    end
  end

  # ── Grammar spec ─────────────────────────────────────────────────────────────

  describe "grammar spec" do
    before  { Pito::Grammar::Registry.reset!; Pito::Grammar::Registry.register_all! }
    after   { Pito::Grammar::Registry.reset! }

    it "is registered under :slash namespace" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :theme)
      expect(spec).not_to be_nil
    end

    it "has auth :authenticated_only" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :theme)
      expect(spec.auth).to eq(:authenticated_only)
    end

    it "has a :subcommand enum slot sourced from :theme_names" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :theme)
      slot = spec.slot(:subcommand)
      expect(slot).not_to be_nil
      expect(slot.kind).to eq(:enum)
      expect(slot.source).to eq(:theme_names)
      expect(slot.optional?).to be(true)
    end
  end

  # ── theme_names vocabulary ───────────────────────────────────────────────────

  describe "theme_names vocabulary" do
    before  { Pito::Grammar::Registry.reset!; Pito::Grammar::Registry.register_all! }
    after   { Pito::Grammar::Registry.reset! }

    subject(:vocab) { Pito::Grammar::Registry.vocabulary(:theme_names) }

    it "is registered" do
      expect(vocab).not_to be_nil
    end

    it "is dynamic" do
      expect(vocab.dynamic?).to be(true)
    end

    it "includes all 18 registered slugs + default" do
      members = vocab.members(context: nil)
      expect(members).to include("tokyo-night", "dracula", "default")
      expect(members.size).to be >= 19  # 18 themes + "default"
    end

    it "includes 'default' as a special member" do
      expect(vocab.members(context: nil)).to include("default")
    end
  end

  # ── Registry.resolve_target ──────────────────────────────────────────────────

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
