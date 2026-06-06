# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe Pito::Hashtag::Handlers::Theme, type: :service do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.create! }
  let(:turn)         { create(:turn, conversation:) }

  def build_message(raw)
    tokens = Pito::Lex::Lexer.call(raw)
    Pito::Hashtag::Parser.call(tokens, raw:)
  end

  def build_handler(raw)
    message = build_message(raw)
    described_class.new(message:, conversation:)
  end

  # Helper: persist a theme_list event in the conversation (simulates /theme list)
  def create_list_event(payload_overrides = {})
    payload = {
      "theme_list" => true,
      "body" => "Pick a theme",
      "sections" => [
        { "title" => "Dark",  "rows" => [ { "key" => "  dracula", "value" => "Dracula" }, { "key" => "  tokyo-night", "value" => "Tokyo Night" } ] },
        { "title" => "Light", "rows" => [ { "key" => "  github-light", "value" => "GitHub Light" } ] }
      ],
      "info_lines" => [ "#preview <name> / #apply <name>" ]
    }.merge(payload_overrides)
    create(:event, conversation:, turn:, kind: "system", position: 1, payload:)
  end

  # ── Registration ──────────────────────────────────────────────────────────────

  describe "handler registration" do
    it "Theme has handle :preview" do
      expect(described_class.handle).to eq(:preview)
    end

    it "ThemeApply has handle :apply" do
      expect(Pito::Hashtag::Handlers::ThemeApply.handle).to eq(:apply)
    end

    it "registers :preview in the hashtag registry after register_all!" do
      orig = Pito::Hashtag::Registry.instance_variable_get(:@registry)&.dup || {}
      Pito::Hashtag::Registry.instance_variable_set(:@registry, {})
      Pito::Hashtag::Registry.register_all!
      expect(Pito::Hashtag::Registry.lookup(:preview)).to eq(described_class)
      Pito::Hashtag::Registry.instance_variable_set(:@registry, orig)
    end

    it "registers :apply in the hashtag registry after register_all!" do
      orig = Pito::Hashtag::Registry.instance_variable_get(:@registry)&.dup || {}
      Pito::Hashtag::Registry.instance_variable_set(:@registry, {})
      Pito::Hashtag::Registry.register_all!
      expect(Pito::Hashtag::Registry.lookup(:apply)).to eq(Pito::Hashtag::Handlers::ThemeApply)
      Pito::Hashtag::Registry.instance_variable_set(:@registry, orig)
    end
  end

  # ── /theme list payload tagging (T12.1) ───────────────────────────────────────

  describe "/theme list — payload tagging" do
    it "includes theme_list: true in the list payload" do
      invocation = Pito::Slash::Invocation.new(
        verb: :theme, args: %w[list], kwargs: {}, raw: "/theme list"
      )
      handler = Pito::Slash::Handlers::Theme.new(invocation:, conversation:)
      payload = handler.call.events.first[:payload]
      expect(payload[:theme_list]).to eq(true)
    end
  end

  # ── #preview <name> with a prior theme_list event ─────────────────────────────

  describe "#call — #preview dracula WITH prior list event" do
    let!(:list_event) { create_list_event }

    subject(:result) { build_handler("#preview dracula").call }

    it "returns Result::Ok with empty events (no append)" do
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
      expect(result.events).to be_empty
    end

    it "updates the list event's kind to theme_diff" do
      result
      expect(list_event.reload.kind).to eq("theme_diff")
    end

    it "retains theme_list: true in the updated payload (so further previews re-find it)" do
      result
      payload = list_event.reload.payload
      expect(payload["theme_list"]).to eq(true)
    end

    it "sets phase: 'preview' in the updated payload" do
      result
      payload = list_event.reload.payload
      expect(payload["phase"]).to eq("preview")
    end

    it "sets previewed_slug to 'dracula'" do
      result
      payload = list_event.reload.payload
      expect(payload["previewed_slug"]).to eq("dracula")
    end

    it "sets theme_diff: true" do
      result
      payload = list_event.reload.payload
      expect(payload["theme_diff"]).to eq(true)
    end

    it "sets granularity to 'char' for dark theme (dracula is :dark)" do
      result
      payload = list_event.reload.payload
      definition = Pito::Themes::Registry.resolve_target("dracula")
      expect(definition.mode).to eq(:dark)
      expect(payload["granularity"]).to eq("char")
    end

    it "includes sections in the updated payload" do
      result
      payload = list_event.reload.payload
      expect(payload["sections"]).to be_an(Array)
      expect(payload["sections"].size).to be >= 2
    end

    it "includes from_text in the updated payload" do
      result
      payload = list_event.reload.payload
      expect(payload["from_text"]).to be_present
    end

    it "does NOT persist the theme in AppSetting" do
      AppSetting.theme = "tokyo-night"
      result
      expect(AppSetting.theme).to eq("tokyo-night")
    end

    it "broadcasts set-theme to pito:global (live-preview)" do
      expect { result }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("set-theme").and include("dracula")
      }
    end

    it "broadcasts a Turbo Stream replace targeting event_<id>" do
      expect { result }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("event_#{list_event.id}")
      }
    end
  end

  # ── #preview is repeatable ────────────────────────────────────────────────────

  describe "#call — #preview repeatability (preview a, then preview b)" do
    let!(:list_event) { create_list_event }

    it "second #preview updates the same event with the new previewed_slug" do
      build_handler("#preview dracula").call
      build_handler("#preview nord").call

      payload = list_event.reload.payload
      expect(payload["previewed_slug"]).to eq("nord")
      expect(payload["theme_list"]).to eq(true)
    end

    it "does not create additional events" do
      expect {
        build_handler("#preview dracula").call
        build_handler("#preview nord").call
      }.not_to change { conversation.events.count }
    end
  end

  # ── #apply <name> with a prior theme_list event ────────────────────────────────

  describe "#call — #apply dracula WITH prior list event (via ThemeApply)" do
    let(:apply_handler_class) { Pito::Hashtag::Handlers::ThemeApply }

    def build_apply_handler(raw)
      message = build_message(raw)
      apply_handler_class.new(message:, conversation:)
    end

    let!(:list_event) { create_list_event }

    subject(:result) { build_apply_handler("#apply dracula").call }

    it "returns Result::Ok with empty events (no append)" do
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
      expect(result.events).to be_empty
    end

    it "updates the list event's kind to theme_diff" do
      result
      expect(list_event.reload.kind).to eq("theme_diff")
    end

    it "sets phase: 'apply'" do
      result
      expect(list_event.reload.payload["phase"]).to eq("apply")
    end

    it "drops theme_list from the payload (list consumed)" do
      result
      payload = list_event.reload.payload
      expect(payload.key?("theme_list")).to be(false)
    end

    it "sets theme_diff: true" do
      result
      expect(list_event.reload.payload["theme_diff"]).to eq(true)
    end

    it "includes a quip body (non-empty string)" do
      result
      expect(list_event.reload.payload["body"]).to be_present
    end

    it "persists dracula in AppSetting" do
      AppSetting.theme = "tokyo-night"
      result
      expect(AppSetting.theme).to eq("dracula")
    end

    it "sets granularity to 'char' for dark theme" do
      result
      expect(list_event.reload.payload["granularity"]).to eq("char")
    end

    it "includes from_text derived from the prior list" do
      result
      expect(list_event.reload.payload["from_text"]).to be_present
    end

    it "broadcasts set-theme to pito:global" do
      expect { result }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("set-theme").and include("dracula")
      }
    end

    it "broadcasts a Turbo Stream replace targeting event_<id>" do
      expect { result }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("event_#{list_event.id}")
      }
    end

    it "does not create additional events" do
      expect { result }.not_to change { conversation.events.count }
    end
  end

  # ── Light theme: line granularity ────────────────────────────────────────────

  describe "granularity — light theme uses 'line'" do
    let!(:list_event) { create_list_event }

    it "sets granularity to 'line' for a light-mode theme" do
      light_def = Pito::Themes::Registry.grouped[:light].first
      expect(light_def).not_to be_nil, "Expected at least one light theme in registry"
      expect(light_def.mode).to eq(:light)

      message = build_message("#preview #{light_def.slug}")
      handler = described_class.new(message:, conversation:)
      handler.call

      expect(list_event.reload.payload["granularity"]).to eq("line")
    end
  end

  # ── Finder picks the most-recent theme_list event ─────────────────────────────

  describe "finder — uses most-recent theme_list event" do
    it "transforms the LAST theme_list event when multiple exist" do
      turn2 = create(:turn, conversation:)
      older_event = create(:event, conversation:, turn:,  kind: "system", position: 2,
                           payload: { "theme_list" => true, "body" => "older list" })
      newer_event = create(:event, conversation:, turn: turn2, kind: "system", position: 3,
                           payload: { "theme_list" => true, "body" => "newer list" })

      build_handler("#preview dracula").call

      expect(newer_event.reload.kind).to eq("theme_diff")
      expect(older_event.reload.kind).to eq("system")
    end
  end

  # ── No prior list → fallback append ──────────────────────────────────────────

  describe "#call — #preview dracula WITHOUT prior list event (fallback)" do
    subject(:result) { build_handler("#preview dracula").call }

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
    end

    it "does NOT persist the theme" do
      AppSetting.theme = "tokyo-night"
      result
      expect(AppSetting.theme).to eq("tokyo-night")
    end

    it "returns a non-empty events array (appended fallback event)" do
      expect(result.events).not_to be_empty
    end

    it "broadcasts set-theme to pito:global" do
      expect { result }.to have_broadcasted_to("pito:global").at_least(:once)
    end
  end

  describe "#call — #apply dracula WITHOUT prior list (fallback, ThemeApply)" do
    it "persists the theme in AppSetting" do
      AppSetting.theme = "tokyo-night"
      message = build_message("#apply dracula")
      Pito::Hashtag::Handlers::ThemeApply.new(message:, conversation:).call
      expect(AppSetting.theme).to eq("dracula")
    end

    it "returns a non-empty events array (appended fallback event)" do
      message = build_message("#apply dracula")
      result  = Pito::Hashtag::Handlers::ThemeApply.new(message:, conversation:).call
      expect(result.events).not_to be_empty
    end
  end

  # ── #apply default (resolves to tokyo-night) ──────────────────────────────────

  describe "#call — #apply default (ThemeApply, fallback path)" do
    it "persists 'tokyo-night' (the default)" do
      AppSetting.theme = "dracula"
      message = build_message("#apply default")
      Pito::Hashtag::Handlers::ThemeApply.new(message:, conversation:).call
      expect(AppSetting.theme).to eq("tokyo-night")
    end
  end

  # ── unknown theme name ────────────────────────────────────────────────────────

  describe "#call — #preview unknown-theme" do
    it "returns Result::Error" do
      result = build_handler("#preview no-such-theme").call
      expect(result).to be_a(Pito::Hashtag::Result::Error)
      expect(result.message_key).to eq("pito.hashtag.theme.errors.unknown_target")
      expect(result.message_args[:name]).to eq("no-such-theme")
    end
  end

  describe "#call — #apply unknown-theme (ThemeApply)" do
    it "returns Result::Error" do
      message = build_message("#apply no-such-theme")
      result  = Pito::Hashtag::Handlers::ThemeApply.new(message:, conversation:).call
      expect(result).to be_a(Pito::Hashtag::Result::Error)
      expect(result.message_key).to eq("pito.hashtag.theme.errors.unknown_target")
    end
  end

  # ── missing name ──────────────────────────────────────────────────────────────

  describe "#call — #preview (no name)" do
    it "returns Result::Error with missing_name key" do
      result = build_handler("#preview").call
      expect(result).to be_a(Pito::Hashtag::Result::Error)
      expect(result.message_key).to eq("pito.hashtag.theme.errors.missing_name")
    end
  end

  describe "#call — #apply (no name, ThemeApply)" do
    it "returns Result::Error with missing_name key" do
      message = build_message("#apply")
      result  = Pito::Hashtag::Handlers::ThemeApply.new(message:, conversation:).call
      expect(result).to be_a(Pito::Hashtag::Result::Error)
      expect(result.message_key).to eq("pito.hashtag.theme.errors.missing_name")
    end
  end

  # ── Dispatcher integration ────────────────────────────────────────────────────

  describe "Dispatcher.call" do
    before do
      Pito::Hashtag::Registry.register(Pito::Hashtag::Handlers::Theme)
      Pito::Hashtag::Registry.register(Pito::Hashtag::Handlers::ThemeApply)
    end

    after do
      Pito::Hashtag::Registry.instance_variable_get(:@registry)&.delete(:preview)
      Pito::Hashtag::Registry.instance_variable_get(:@registry)&.delete(:apply)
    end

    it "dispatches #preview dracula to Theme handler" do
      result = Pito::Hashtag::Dispatcher.call(input: "#preview dracula", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
    end

    it "dispatches #apply dracula to ThemeApply handler and persists" do
      AppSetting.theme = "tokyo-night"
      result = Pito::Hashtag::Dispatcher.call(input: "#apply dracula", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
      expect(AppSetting.theme).to eq("dracula")
    end

    it "returns error for unknown theme name" do
      result = Pito::Hashtag::Dispatcher.call(input: "#preview ghost-theme", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Error)
      expect(result.message_key).to eq("pito.hashtag.theme.errors.unknown_target")
    end
  end
end
