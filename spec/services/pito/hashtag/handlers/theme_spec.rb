# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe Pito::Hashtag::Handlers::Theme, type: :service do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.create! }

  def build_message(raw)
    tokens = Pito::Lex::Lexer.call(raw)
    Pito::Hashtag::Parser.call(tokens, raw:)
  end

  def build_handler(raw)
    message = build_message(raw)
    described_class.new(message:, conversation:)
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

  # ── #preview <name> ───────────────────────────────────────────────────────────

  describe "#call — #preview dracula" do
    subject(:result) { build_handler("#preview dracula").call }

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
    end

    it "does NOT persist the theme" do
      AppSetting.theme = "tokyo-night"
      result
      expect(AppSetting.theme).to eq("tokyo-night")
    end

    it "broadcasts set-theme to pito:global" do
      expect {
        result
      }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("set-theme")
        expect(content).to include("dracula")
      }
    end

    it "returns a system event with confirmation text" do
      text = result.events.first[:payload][:text]
      expect(text).to be_present
      expect(text.downcase).to include("dracula").or include("preview")
    end
  end

  # ── #apply <name> ─────────────────────────────────────────────────────────────

  describe "#call — #apply via ThemeApply handler" do
    let(:apply_handler) { Pito::Hashtag::Handlers::ThemeApply }

    def build_apply_handler(raw)
      message = build_message(raw)
      apply_handler.new(message:, conversation:)
    end

    subject(:result) { build_apply_handler("#apply dracula").call }

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
    end

    it "persists the theme in AppSetting" do
      AppSetting.theme = "tokyo-night"
      result
      expect(AppSetting.theme).to eq("dracula")
    end

    it "broadcasts set-theme to pito:global" do
      expect {
        result
      }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("set-theme")
        expect(content).to include("dracula")
      }
    end

    it "returns a system event confirming the theme change" do
      text = result.events.first[:payload][:text]
      expect(text).to be_present
      expect(text.downcase).to include("dracula").or include("theme")
    end
  end

  # ── #apply default (resolves to tokyo-night) ──────────────────────────────────

  describe "#call — #apply default (ThemeApply)" do
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
