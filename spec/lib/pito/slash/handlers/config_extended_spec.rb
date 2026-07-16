# frozen_string_literal: true

# Extended coverage for Pito::Slash::Handlers::Config.
# The main config_spec.rb covers core getter/setter/toggle paths.
# This file adds: provider --help tables, igdb/webhook setters,
# bare /config overview, toggle getter for fx, and the ai/tavily providers
# (the ordered set_ai_values path: provider → api_key → model → effort).

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Config, "extended coverage", type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(args: [], kwargs: {}, raw: nil)
    invocation = Pito::Slash::Invocation.new(
      tool:   :config,
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

    it "renders a man-page listing all config providers (sound; motion/fx removed)" do
      body = build_handler(raw: "/config").call.events.first[:payload]["body"]
      expect(body).to include("pito-help-block")
      %w[google igdb webhook sound timezone].each { |p| expect(body).to include(p) }
      # The nickname provider is PURGED (2.0.0) — never advertised again.
      expect(Pito::Slash::HelpBuilder::ALL_CONFIG_PROVIDERS).not_to include("me")
    end

    it "renders a man-page help body" do
      payload = build_handler(raw: "/config").call.events.first[:payload]
      expect(payload["html"]).to be true
      expect(payload["body"]).to include("pito-help-block")
      expect(payload["body"]).to include("Usage:")
    end
  end

  # ── Provider --help tables ───────────────────────────────────────────────────

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

  # ── AI provider (ordered kwargs: provider → api_key → model → effort) ────────

  describe "#call — /config ai provider=... model=... (setter)" do
    before do
      allow(::Ai::ModelCatalog).to receive(:models).with(provider: :opencode)
        .and_return([ { id: "claude-sonnet-5", pinned: false } ])
    end

    it "persists ai_provider and ai_model and confirms via the shared updated copy" do
      result = build_handler(args: [ "ai" ], kwargs: { provider: "opencode", model: "claude-sonnet-5" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.get("ai_provider")).to eq("opencode")
      expect(AppSetting.get("ai_model")).to eq("claude-sonnet-5")
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.config.updated")
      expect(result.events.first[:payload][:message_args][:provider]).to eq("ai")
    end
  end

  describe "#call — /config ai api_key=... (setter, scoped to the active provider)" do
    it "stores the key under <provider>_api_key for the default/active provider (opencode)" do
      result = build_handler(args: [ "ai" ], kwargs: { api_key: "sk-secret" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.get("opencode_api_key")).to eq("sk-secret")
    end

    it "never echoes the raw key back and is masked in recall by Pito::InputMasking" do
      result = build_handler(args: [ "ai" ], kwargs: { api_key: "sk-secret" }).call
      expect(result.events.first[:payload][:message_args][:keys]).to eq("api_key")
      expect(result.events.first[:payload].to_s).not_to include("sk-secret")

      input = "/config ai api_key=sk-secret"
      expect(Pito::InputMasking.mask_config_credentials(input)).to eq("/config ai api_key=***")
    end
  end

  describe "#call — /config ai effort=... (per-model effort map)" do
    before do
      AppSetting.set("ai_provider", "opencode")
      AppSetting.set("ai_model", "claude-sonnet-5")
    end

    it "writes the effort keyed to the currently active provider/model" do
      result = build_handler(args: [ "ai" ], kwargs: { effort: "high" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.ai_effort_for("opencode/claude-sonnet-5")).to eq("high")
    end
  end

  describe "#call — /config ai provider=X model=Y effort=Z (ordered application in one command)" do
    before do
      AppSetting.set("ai_provider", "opencode")
      AppSetting.set("ai_model", "claude-sonnet-5")
      AppSetting.set_ai_effort("opencode/claude-sonnet-5", "low")

      allow(::Ai::ModelCatalog).to receive(:models).with(provider: :openrouter)
        .and_return([ { id: "some-model", pinned: false } ])
    end

    it "applies provider first, then model, then effort — effort lands on the NEW provider/model" do
      result = build_handler(
        args:   [ "ai" ],
        kwargs: { provider: "openrouter", model: "some-model", effort: "medium" }
      ).call

      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.get("ai_provider")).to eq("openrouter")
      expect(AppSetting.get("ai_model")).to eq("some-model")
      expect(AppSetting.ai_effort_for("openrouter/some-model")).to eq("medium")
      expect(AppSetting.ai_effort_for("opencode/claude-sonnet-5")).to eq("low") # untouched
    end
  end

  describe "#call — /config ai (unknown kwarg)" do
    it "returns the shared unknown_keys error, same as other providers" do
      result = build_handler(args: [ "ai" ], kwargs: { nonsense: "1" }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
      expect(result.message_args[:provider]).to eq("ai")
    end
  end

  # ── Tavily setter (the @ai --web search backend) ─────────────────────────────

  describe "#call — /config tavily api_key=... (setter)" do
    it "persists the tavily_api_key" do
      result = build_handler(args: [ "tavily" ], kwargs: { api_key: "tvly-secret" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.get("tavily_api_key")).to eq("tvly-secret")
    end
  end

  # ── Embeddings status provider (P8, 3.0.1) ───────────────────────────────────
  # Read-only: embedder reachability (stubbed — never hits the real sidecar)
  # + embedded/total counts for games, vids, conversation events, nl_examples.

  describe "#call — /config embeddings (getter, read-only status block)" do
    def row_value(result, label)
      result.events.first[:payload][:table_rows].find { |r| r[:key] == "#{label}:" }&.dig(:value)
    end

    it "shows OK + embedded/total counts when the sidecar is reachable" do
      allow_any_instance_of(Pito::Embedding::Client).to receive(:healthy?).and_return(true)

      create(:game, Game::EMBEDDING_COLUMN => Array.new(768, 0.1))
      create(:game)

      create(:video, Video::EMBEDDING_COLUMN => Array.new(768, 0.1))
      create(:video)
      create(:video)

      embeddable_kind = Pito::Embedding::EventIndexer::EMBEDDABLE_KINDS.first
      create(:event, kind: embeddable_kind, embedding: Array.new(768, 0.1))
      create(:event, kind: embeddable_kind)
      create(:event, kind: "thinking") # not embeddable — excluded from the scope entirely

      Pito::Nl::Router::Example.create!(tool: "list", phrase: "embedded phrase", digest: "d-embedded",
                                         embedding: Array.new(768, 0.1))
      Pito::Nl::Router::Example.create!(tool: "list", phrase: "pending phrase", digest: "d-pending")

      result = build_handler(args: [ "embeddings" ], raw: "/config embeddings").call

      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(row_value(result, "Embedder")).to eq(I18n.t("pito.slash.config.status.ok"))
      expect(row_value(result, "Games")).to eq("1/2")
      expect(row_value(result, "Vids")).to eq("1/3")
      expect(row_value(result, "Conversation events")).to eq("1/2")
      expect(row_value(result, "NL examples")).to eq("1/2")
    end

    it "shows MISSING for the embedder when the sidecar is unreachable" do
      allow_any_instance_of(Pito::Embedding::Client).to receive(:healthy?).and_return(false)

      result = build_handler(args: [ "embeddings" ], raw: "/config embeddings").call

      expect(row_value(result, "Embedder")).to eq(I18n.t("pito.slash.config.status.missing"))
    end

    it "/config embeddings foo=bar (stray kwarg) → unknown_keys error, not a crash" do
      result = build_handler(args: [ "embeddings" ], kwargs: { foo: "bar" }).call

      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
    end
  end
end
