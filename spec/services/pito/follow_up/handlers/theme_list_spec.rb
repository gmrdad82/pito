# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe Pito::FollowUp::Handlers::ThemeList, type: :service do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.create! }
  let(:turn)         { create(:turn, conversation:) }

  # Build a stamped theme-list event (simulates /theme list with the engine stamp).
  def create_list_event(extra_payload = {})
    payload = {
      "body"    => "18 themes, two vibes. Pick one below.",
      "sections" => [
        { "title" => "Dark",
          "rows"  => [
            { "key" => "  dracula",     "value" => "Dracula" },
            { "key" => "  tokyo-night", "value" => "Tokyo Night" }
          ] },
        { "title" => "Light",
          "rows"  => [
            { "key" => "  github-light", "value" => "GitHub Light" }
          ] }
      ],
      "reply_handle" => "beta-1234",
      "reply_target" => "theme_list"
    }.merge(extra_payload)
    create(:event, conversation:, turn:, kind: "system", position: 1, payload:)
  end

  def call(event, rest)
    described_class.new.call(event:, rest:, conversation:)
  end

  # ── Registration ──────────────────────────────────────────────────────────────

  describe "registration" do
    it "is registered under 'theme_list'" do
      expect(Pito::FollowUp::Registry.for("theme_list")).to eq(described_class)
    end

    it "has mode :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("theme_list")).to eq(:mutate)
    end
  end

  # ── preview action ────────────────────────────────────────────────────────────

  describe "#call — preview dracula" do
    let!(:event) { create_list_event }

    subject(:result) { call(event, "preview dracula") }

    it "returns a Result::Mutation" do
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "returns kind 'theme_diff'" do
      expect(result.kind).to eq("theme_diff")
    end

    it "sets phase to 'preview'" do
      expect(result.payload["phase"]).to eq("preview")
    end

    it "sets previewed_slug to 'dracula'" do
      expect(result.payload["previewed_slug"]).to eq("dracula")
    end

    it "sets granularity to 'char' for dark theme" do
      expect(result.payload["granularity"]).to eq("char")
    end

    it "includes sections (Dark/Light)" do
      expect(result.payload["sections"]).to be_an(Array)
      expect(result.payload["sections"].size).to be >= 2
    end

    it "includes from_text derived from the event payload" do
      expect(result.payload["from_text"]).to be_present
    end

    it "RETAINS reply_handle (stays follow-up-able)" do
      expect(result.payload["reply_handle"]).to eq("beta-1234")
    end

    it "RETAINS reply_target" do
      expect(result.payload["reply_target"]).to eq("theme_list")
    end

    it "does NOT set reply_consumed (remains routable)" do
      expect(result.payload["reply_consumed"]).to be_nil
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
  end

  # ── preview with light theme: line granularity ────────────────────────────────

  describe "#call — preview light theme → granularity 'line'" do
    let!(:event) { create_list_event }

    it "sets granularity to 'line' for a light-mode theme" do
      light_def = Pito::Themes::Registry.grouped[:light].first
      expect(light_def).not_to be_nil
      result = call(event, "preview #{light_def.slug}")
      expect(result.payload["granularity"]).to eq("line")
    end
  end

  # ── preview is repeatable ─────────────────────────────────────────────────────

  describe "#call — preview is repeatable" do
    let!(:event) { create_list_event }

    it "a second preview call returns a Mutation with the new slug (still no reply_consumed)" do
      # Simulate the engine mutating the event after the first preview.
      first_result = call(event, "preview dracula")
      event.update!(kind: first_result.kind, payload: first_result.payload)

      second_result = call(event, "preview nord")
      expect(second_result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(second_result.payload["previewed_slug"]).to eq("nord")
      expect(second_result.payload["reply_consumed"]).to be_nil
    end
  end

  # ── apply action ──────────────────────────────────────────────────────────────

  describe "#call — apply dracula" do
    let!(:event) { create_list_event }

    subject(:result) { call(event, "apply dracula") }

    it "returns a Result::Mutation" do
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "returns kind 'theme_diff'" do
      expect(result.kind).to eq("theme_diff")
    end

    it "sets phase to 'apply'" do
      expect(result.payload["phase"]).to eq("apply")
    end

    it "sets granularity to 'char' for dark theme (dracula)" do
      expect(result.payload["granularity"]).to eq("char")
    end

    it "includes a non-empty quip body" do
      expect(result.payload["body"]).to be_present
    end

    it "includes from_text" do
      expect(result.payload["from_text"]).to be_present
    end

    it "sets reply_consumed: true (no further replies)" do
      expect(result.payload["reply_consumed"]).to eq(true)
    end

    it "retains reply_handle (handle stays reserved)" do
      expect(result.payload["reply_handle"]).to eq("beta-1234")
    end

    it "retains reply_target" do
      expect(result.payload["reply_target"]).to eq("theme_list")
    end

    it "persists dracula in AppSetting" do
      AppSetting.theme = "tokyo-night"
      result
      expect(AppSetting.theme).to eq("dracula")
    end

    it "broadcasts set-theme to pito:global" do
      expect { result }.to have_broadcasted_to("pito:global").with { |msg|
        content = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(content).to include("set-theme").and include("dracula")
      }
    end
  end

  # ── apply 'default' resolves to tokyo-night ────────────────────────────────────

  describe "#call — apply default" do
    let!(:event) { create_list_event }

    it "persists 'tokyo-night' (the default)" do
      AppSetting.theme = "dracula"
      result = call(event, "apply default")
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(AppSetting.theme).to eq("tokyo-night")
    end
  end

  # ── invalid action ────────────────────────────────────────────────────────────

  describe "#call — invalid action" do
    let!(:event) { create_list_event }

    it "returns Result::Error for unknown action" do
      result = call(event, "explode dracula")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.theme_list.errors.invalid_action")
      expect(result.message_args[:action]).to eq("explode")
    end
  end

  # ── missing name ──────────────────────────────────────────────────────────────

  describe "#call — missing name" do
    let!(:event) { create_list_event }

    it "returns Result::Error when name is blank for preview" do
      result = call(event, "preview")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.theme_list.errors.missing_name")
    end

    it "returns Result::Error when name is blank for apply" do
      result = call(event, "apply")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.theme_list.errors.missing_name")
    end
  end

  # ── unknown target ────────────────────────────────────────────────────────────

  describe "#call — unknown theme name" do
    let!(:event) { create_list_event }

    it "returns Result::Error for unknown theme name on preview" do
      result = call(event, "preview no-such-theme")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.theme_list.errors.unknown_target")
      expect(result.message_args[:name]).to eq("no-such-theme")
    end

    it "returns Result::Error for unknown theme name on apply" do
      result = call(event, "apply no-such-theme")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.theme_list.errors.unknown_target")
    end
  end

  # ── payload_to_plain_text (via from_text) ────────────────────────────────────

  describe "from_text captures list content" do
    let!(:event) { create_list_event }

    it "from_text includes body text" do
      result = call(event, "preview dracula")
      expect(result.payload["from_text"]).to include("18 themes")
    end

    it "from_text includes section titles" do
      result = call(event, "preview dracula")
      expect(result.payload["from_text"]).to include("Dark").and include("Light")
    end

    it "from_text includes row slugs" do
      result = call(event, "preview dracula")
      expect(result.payload["from_text"]).to include("dracula")
    end
  end
end
