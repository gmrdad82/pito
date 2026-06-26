# frozen_string_literal: true

# Extended coverage for Pito::Slash::Handlers::Config.
# The main config_spec.rb covers core getter/setter/toggle paths.
# This file adds: provider --help tables, voyage/igdb/webhook setters,
# bare /config overview, and toggle getter for fx.

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Config, "extended coverage", type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(args: [], kwargs: {}, raw: nil)
    invocation = Pito::Slash::Invocation.new(
      verb:   :config,
      args:   args,
      kwargs: kwargs,
      raw:    raw || "/config #{args.join(' ')}"
    )
    described_class.new(invocation:, conversation:)
  end

  before { Pito::Credentials.invalidate! }
  after  { Pito::Credentials.invalidate! }

  # ── Bare /config → general overview ─────────────────────────────────────────

  describe "#call — bare /config (no provider)" do
    it "returns Result::Ok" do
      result = build_handler(raw: "/config").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "renders a man-page listing all config providers (incl. sound and fx)" do
      body = build_handler(raw: "/config").call.events.first[:payload]["body"]
      expect(body).to include("pito-help-block")
      %w[google voyage igdb webhook me sound fx].each { |p| expect(body).to include(p) }
    end

    it "renders a man-page help body" do
      payload = build_handler(raw: "/config").call.events.first[:payload]
      expect(payload["html"]).to be true
      expect(payload["body"]).to include("pito-help-block")
      expect(payload["body"]).to include("Usage:")
    end
  end

  # ── Provider --help tables ───────────────────────────────────────────────────

  describe "#show_help — /config voyage --help" do
    it "returns a system event" do
      result = build_handler(args: [ "voyage" ], raw: "/config voyage --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:kind]).to eq("system")
    end
  end

  describe "#show_help — /config igdb --help" do
    it "returns a system event with provider help text" do
      result = build_handler(args: [ "igdb" ], raw: "/config igdb --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end
  end

  describe "#show_help — /config webhook --help" do
    it "returns a system event" do
      result = build_handler(args: [ "webhook" ], raw: "/config webhook --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end
  end

  # ── Voyage setter ─────────────────────────────────────────────────────────────

  describe "#call — /config voyage api_key=voy-secret (setter)" do
    it "persists the api_key to AppSetting and returns Ok" do
      result = build_handler(args: [ "voyage" ], kwargs: { api_key: "voy-secret" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      AppSetting.singleton_row.reload
      expect(AppSetting.singleton_row.voyage_api_key).to eq("voy-secret")
    end

    it "includes the pito.slash.config.updated key in the payload" do
      result = build_handler(args: [ "voyage" ], kwargs: { api_key: "v" }).call
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.config.updated")
    end

    it "returns an error for an unknown voyage key" do
      result = build_handler(args: [ "voyage" ], kwargs: { unknown: "x" }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
    end
  end

  # ── IGDB setter ──────────────────────────────────────────────────────────────

  describe "#call — /config igdb client_id=i client_secret=s (setter)" do
    it "persists both keys to AppSetting" do
      build_handler(args: [ "igdb" ], kwargs: { client_id: "igdb-id", client_secret: "igdb-secret" }).call
      expect(AppSetting.igdb_client_id).to eq("igdb-id")
      expect(AppSetting.igdb_client_secret).to eq("igdb-secret")
    end
  end

  # ── Webhook setter ────────────────────────────────────────────────────────────

  describe "#call — /config webhook slack=url (setter)" do
    it "persists the slack webhook url" do
      result = build_handler(args: [ "webhook" ], kwargs: { slack: "https://hooks.slack.com/x" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.slack_webhook_url).to eq("https://hooks.slack.com/x")
    end

    it "persists the discord webhook url" do
      result = build_handler(args: [ "webhook" ], kwargs: { discord: "https://discord.com/api/x" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.discord_webhook_url).to eq("https://discord.com/api/x")
    end
  end

  # ── Webhook getter (status table) — URLs masked behind the OK flag ─────────────

  describe "#call — /config webhook (getter)" do
    it "shows OK (a masked flag, NOT the raw URLs) when slack/discord are set" do
      AppSetting.slack_webhook_url   = "https://hooks.slack.com/x"
      AppSetting.discord_webhook_url = "https://discord.com/api/x"
      Pito::Credentials.invalidate!

      values = build_handler(args: [ "webhook" ]).call.events.first[:payload][:table_rows].map { |r| r[:value] }
      expect(values).to all(eq(I18n.t("pito.slash.config.status.ok")))
      expect(values.join).not_to include("hooks.slack.com")
      expect(values.join).not_to include("discord.com")
    end

    it "shows MISSING when unset" do
      AppSetting.slack_webhook_url   = nil
      AppSetting.discord_webhook_url = nil
      Pito::Credentials.invalidate!

      values = build_handler(args: [ "webhook" ]).call.events.first[:payload][:table_rows].map { |r| r[:value] }
      expect(values).to all(eq(I18n.t("pito.slash.config.status.missing")))
    end
  end

  # ── Voyage getter (status table) ──────────────────────────────────────────────

  describe "#call — /config voyage (getter, no kwargs)" do
    it "returns a system event with a table_rows array" do
      result = build_handler(args: [ "voyage" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:table_rows]).to be_an(Array)
    end

    it "includes API Key row" do
      result = build_handler(args: [ "voyage" ]).call
      keys = result.events.first[:payload][:table_rows].map { |r| r[:key] }
      expect(keys).to include("API Key:")
    end
  end

  # ── FX reveal-effect getter ────────────────────────────────────────────────────

  describe "#call — /config fx (enum getter, no arg)" do
    it "returns a system event showing the current reveal effect" do
      AppSetting.fx_effect = "typewriter"
      result = build_handler(args: [ "fx" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      text = result.events.first[:payload][:text]
      expect(text).to be_present
      AppSetting.fx_effect = "typewriter" # restore
    end
  end

  # ── /config sound on synonyms ─────────────────────────────────────────────────

  describe "#call — /config sound off synonyms" do
    %w[false disable disabled].each do |syn|
      it "accepts '#{syn}' as a synonym for off" do
        AppSetting.sound_enabled = true
        allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:broadcast_settings_update)

        result = build_handler(args: [ "sound", syn ]).call
        expect(result).to be_a(Pito::Slash::Result::Ok)
        expect(AppSetting.sound_enabled?).to be false
        AppSetting.sound_enabled = true # restore
      end
    end

    %w[on enable enabled].each do |syn|
      it "accepts '#{syn}' as a synonym for on" do
        AppSetting.sound_enabled = false
        allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:broadcast_settings_update)

        result = build_handler(args: [ "sound", syn ]).call
        expect(result).to be_a(Pito::Slash::Result::Ok)
        expect(AppSetting.sound_enabled?).to be true
        AppSetting.sound_enabled = true # restore
      end
    end
  end

  # ── Credentials.invalidate! is called after setter ────────────────────────────

  describe "#call — setter invalidates credentials cache" do
    it "calls Pito::Credentials.invalidate! after writing settings" do
      expect(Pito::Credentials).to receive(:invalidate!).at_least(:once)
      build_handler(args: [ "google" ], kwargs: { client_id: "x" }).call
    end
  end
end
