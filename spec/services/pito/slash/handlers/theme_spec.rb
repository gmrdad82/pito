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

  # ── P6: /theme ls alias of /theme list ──────────────────────────────────────
  #
  # `ls` is a vocabulary synonym for `list` in THEME_SUBCOMMANDS.  The handler
  # resolves the raw arg before dispatch, so `/theme ls` routes identically to
  # `/theme list`.  These specs confirm parity and guard the synonym registration.

  describe "#call — /theme ls (alias of /theme list)" do
    it "returns Result::Ok — same as /theme list" do
      result_ls   = build_handler(args: %w[ls]).call
      result_list = build_handler(args: %w[list]).call
      expect(result_ls).to be_a(Pito::Slash::Result::Ok)
      expect(result_list).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns the same payload text as /theme list" do
      text_ls   = build_handler(args: %w[ls]).call.events.first[:payload][:text]
      text_list = build_handler(args: %w[list]).call.events.first[:payload][:text]
      expect(text_ls).to eq(text_list)
    end

    it "does NOT persist a theme (it is a list operation, not apply)" do
      AppSetting.theme = "tokyo-night"
      build_handler(args: %w[ls]).call
      expect(AppSetting.theme).to eq("tokyo-night")
    end
  end

  # ── THEME_SUBCOMMANDS vocabulary unit spec (alias mechanism) ─────────────────
  #
  # These are the grammar-level unit specs for the vocabulary synonym mechanism
  # itself — independent of the handler dispatch path.

  describe "Pito::Grammar::Vocabularies::THEME_SUBCOMMANDS" do
    subject(:vocab) { Pito::Grammar::Vocabularies::THEME_SUBCOMMANDS }

    it "is a Pito::Grammar::Vocabulary" do
      expect(vocab).to be_a(Pito::Grammar::Vocabulary)
    end

    it "is static (not dynamic)" do
      expect(vocab.dynamic?).to be(false)
    end

    it "has canonical subcommand names" do
      expect(vocab.canonical).to include("list", "preview", "apply", "reset")
    end

    it "does NOT include ls in canonical (it is a synonym)" do
      expect(vocab.canonical).not_to include("ls")
    end

    it 'resolves "ls" to "list"' do
      expect(vocab.resolve("ls")).to eq("list")
    end

    it 'resolves "LS" to "list" (case-insensitive)' do
      expect(vocab.resolve("LS")).to eq("list")
    end

    it 'resolves "list" to "list" (canonical pass-through)' do
      expect(vocab.resolve("list")).to eq("list")
    end

    it 'resolves "preview" to "preview"' do
      expect(vocab.resolve("preview")).to eq("preview")
    end

    it 'resolves "apply" to "apply"' do
      expect(vocab.resolve("apply")).to eq("apply")
    end

    it 'resolves "reset" to "reset"' do
      expect(vocab.resolve("reset")).to eq("reset")
    end

    it "returns nil for an unknown token" do
      expect(vocab.resolve("unknown-cmd")).to be_nil
    end

    it "is registered in the grammar registry after register_all!" do
      Pito::Grammar::Registry.reset!
      Pito::Grammar::Registry.register_all!
      expect(Pito::Grammar::Registry.vocabulary(:theme_subcommands)).to eq(vocab)
      Pito::Grammar::Registry.reset!
    end

    it "is included in Vocabularies.all" do
      expect(Pito::Grammar::Vocabularies.all).to include(vocab)
    end
  end

  # ── P6: Autocomplete — ls hidden, list offered via theme_names ───────────────
  #
  # The handler's grammar slot is sourced from :theme_names (slugs + "default"),
  # not :theme_subcommands.  Autocomplete for `/theme <partial>` suggests theme
  # slugs and "default", never the subcommand keywords.  `ls` does not appear.
  # This is intentional: subcommands are handler-internal dispatch tokens,
  # not vocabulary members surfaced to the user via autocomplete.

  describe "autocomplete — /theme arg stage" do
    before { Pito::Grammar::Registry.reset!; Pito::Grammar::Registry.register_all! }
    after  { Pito::Grammar::Registry.reset! }

    def autocomplete(input)
      Pito::Autocomplete::Engine.call(
        input:         input,
        cursor:        input.length,
        authenticated: true
      )
    end

    it "suggests theme slugs (not ls) when typing after /theme " do
      result = autocomplete("/theme ")
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("dracula", "tokyo-night")
    end

    it "does not suggest ls as an autocomplete item" do
      result = autocomplete("/theme l")
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).not_to include("ls")
    end

    it "does not suggest list as an autocomplete item (not a theme slug)" do
      result = autocomplete("/theme l")
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).not_to include("list")
    end
  end
end
