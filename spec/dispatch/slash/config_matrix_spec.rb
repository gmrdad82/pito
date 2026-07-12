# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/config` (recognition only, all writes mocked) ──────────
#
# RULE: every subcommand / kwarg combination Pito::Slash::Handlers::Config
# recognises is exercised here — no exception. We assert what the handler
# ACTUALLY does, not what the comment claims; any mismatch is a RECOGNITION BUG
# documented in-line.
#
# ── What is mocked ──────────────────────────────────────────────────────────
# • AppSetting.singleton_row.update! (google client_id/secret, voyage api_key)
# • All AppSetting class-level writer methods (redirect_uri=, igdb_client_id=, …)
# • All AppSetting class-level reader methods (sound_enabled?, …)
#   → deterministic defaults so getter paths return predictable text
# • Pito::Credentials.* reader methods (for provider status display)
# • Pito::Credentials.invalidate!
# • Pito::Stream::Broadcaster.new + #broadcast_settings_update
# • Pito::Stream::Broadcaster.broadcast_global_mini_status
#
# ── What is NOT mocked ───────────────────────────────────────────────────────
# • ActiveSupport::TimeZone lookups (pure library, no DB)
# • I18n (uses real locale files — spec fails fast if a copy key is missing)
# • Pito::Copy.render (real, uses I18n)
# • Pito::MessageBuilder::ManPage.render (real, produces HTML strings)
#
# ── Auth gate ────────────────────────────────────────────────────────────────
# The grammar spec marks /config as :authenticated_only. Enforcement lives in
# ChatDispatchJob (NOT in the handler or the Pito::Slash::Dispatcher). Passing
# authenticated: false to the handler therefore does NOT block execution.
# See "grammar-level auth requirement" section below.
#
# ── No RECOGNITION BUGS found ────────────────────────────────────────────────
# All forms behave exactly as the handler comment describes.
RSpec.describe "Dispatch matrix — /config (recognition, mocked)", type: :dispatch do
  let(:conversation)   { double("conversation") }
  let(:singleton_row)  { double("AppSetting::SingletonRow") }
  let(:broadcaster)    { instance_double(Pito::Stream::Broadcaster, broadcast_settings_update: nil) }

  # Build a handler directly (bypasses Dispatcher arity guard + --help intercept).
  # The handler's own `help?` check fires when raw contains "--help".
  def build_handler(args: [], kwargs: {}, raw: nil, authenticated: true)
    raw ||= args.empty? ? "/config" : "/config #{args.join(' ')}"
    invocation = Pito::Slash::Invocation.new(tool: :config, args:, kwargs:, raw:)
    Pito::Slash::Handlers::Config.new(invocation:, conversation:, authenticated:)
  end

  before do
    # ── AppSetting singleton row (google client_id/secret + voyage api_key go here)
    allow(singleton_row).to receive(:update!)
    allow(AppSetting).to receive(:singleton_row).and_return(singleton_row)

    # ── AppSetting class-level writers (igdb, webhook, sound, me, tz)
    allow(AppSetting).to receive(:google_oauth_redirect_uri=)
    allow(AppSetting).to receive(:google_api_key=)
    allow(AppSetting).to receive(:igdb_client_id=)
    allow(AppSetting).to receive(:igdb_client_secret=)
    allow(AppSetting).to receive(:slack_webhook_url=)
    allow(AppSetting).to receive(:discord_webhook_url=)
    allow(AppSetting).to receive(:sound_enabled=)
    allow(AppSetting).to receive(:timezone=)

    # ── Cache invalidation: no-op
    allow(Pito::Credentials).to receive(:invalidate!)

    # ── AppSetting readers: deterministic defaults
    allow(AppSetting).to receive(:sound_enabled?).and_return(true)
    allow(AppSetting).to receive(:timezone).and_return("UTC")

    # ── Pito::Credentials readers (used by PROVIDER_STATUS lambdas in show_status)
    allow(Pito::Credentials).to receive(:google_oauth_client_id).and_return("set")
    allow(Pito::Credentials).to receive(:google_oauth_client_secret).and_return(nil)
    allow(Pito::Credentials).to receive(:google_oauth_redirect_uri).and_return(nil)
    allow(Pito::Credentials).to receive(:google_api_key).and_return(nil)
    allow(Pito::Credentials).to receive(:voyage_api_key).and_return(nil)
    allow(Pito::Credentials).to receive(:igdb_client_id).and_return(nil)
    allow(Pito::Credentials).to receive(:igdb_client_secret).and_return(nil)
    allow(Pito::Credentials).to receive(:slack_webhook_url).and_return(nil)
    allow(Pito::Credentials).to receive(:discord_webhook_url).and_return(nil)

    # ── Broadcaster: no-op
    allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
    allow(Pito::Stream::Broadcaster).to receive(:broadcast_global_mini_status)
  end

  # ── Grammar-level auth requirement ─────────────────────────────────────────
  describe "grammar-level auth requirement" do
    it "/config is :authenticated_only in the grammar spec" do
      expect(parsed_intent("/config")[:auth]).to eq(:authenticated_only)
    end

    it "the handler itself does NOT gate on authenticated: (enforcement is in ChatDispatchJob)" do
      # Calling the handler directly with authenticated: false still returns a result.
      # The real auth block lives in ChatDispatchJob, above the Dispatcher.
      result = build_handler(args: [], raw: "/config", authenticated: false).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end
  end

  # ── Bare /config (no provider, no --help) ───────────────────────────────────
  describe "bare /config → general overview" do
    it "returns Result::Ok with an HTML man-page system event" do
      result = build_handler(raw: "/config").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload["html"]).to be true
      expect(payload["body"]).to include("pito-help-block")
    end

    it "lists all providers in the overview body (motion/fx removed — item 18)" do
      result = build_handler(raw: "/config").call
      body = result.events.first[:payload]["body"]
      %w[google voyage igdb webhook me sound timezone].each do |p|
        expect(body).to include(p), "expected overview to include provider '#{p}'"
      end
    end
  end

  # ── --help forms ─────────────────────────────────────────────────────────────
  #
  # The handler's `call` checks `help?` (raw includes /--help\b/) before any
  # other branching, and delegates to `show_help`. HelpBuilder (called from the
  # Dispatcher) also delegates to `Config#show_help` for the config verb; the
  # result is identical whether we go through Dispatcher or call the handler
  # directly.
  describe "--help flag" do
    {
      "bare /config --help (no provider)"  => [ [], "/config --help" ],
      "/config google --help"              => [ %w[google],  "/config google --help" ],
      "/config voyage --help"              => [ %w[voyage],  "/config voyage --help" ],
      "/config igdb --help"               => [ %w[igdb],    "/config igdb --help" ],
      "/config webhook --help"             => [ %w[webhook], "/config webhook --help" ],
      "/config timezone --help"            => [ %w[timezone], "/config timezone --help" ]
    }.each do |label, (args, raw)|
      it "#{label} → Result::Ok (HTML man-page)" do
        result = build_handler(args:, raw:).call
        expect(result).to be_a(Pito::Slash::Result::Ok)
        payload = result.events.first[:payload]
        expect(payload["html"]).to be true
        expect(payload["body"]).to include("pito-help-block")
      end
    end

    it "/config google --help body contains all google key tokens + /connect hint" do
      result = build_handler(args: %w[google], raw: "/config google --help").call
      body = result.events.first[:payload]["body"]
      %w[client_id= client_secret= redirect_uri= api_key=].each do |key|
        expect(body).to include(key)
      end
      expect(body).to include("/connect")
    end


    it "/config timezone --help body contains /config timezone usage" do
      result = build_handler(args: %w[timezone], raw: "/config timezone --help").call
      body = result.events.first[:payload]["body"]
      expect(body).to include("/config timezone")
    end

    it "unknown provider --help → falls back to general overview (not an error)" do
      # provider_keys_help_man_page returns general_help_man_page when keys.blank?
      result = build_handler(args: %w[nope], raw: "/config nope --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload]["body"]).to include("pito-help-block")
    end
  end

  # ── Unknown provider (no --help) ─────────────────────────────────────────────
  describe "unknown provider" do
    # motion + fx were removed — they are now unknown providers. (openai left
    # this list when the AI provider registry made every ai_providers.yml entry
    # a real /config credential provider.)
    %w[bogus youtube twitch unknown_service 123 foobar motion fx].each do |provider|
      it "/config #{provider} → unknown_provider error" do
        result = build_handler(args: [ provider ]).call
        expect(result).to be_a(Pito::Slash::Result::Error)
        expect(result.message_key).to eq("pito.slash.config.errors.unknown_provider")
        expect(result.message_args[:provider]).to eq(provider)
      end
    end
  end
  # ── Sound toggle ──────────────────────────────────────────────────────────────
  describe "sound toggle" do
    it "/config sound (getter, no arg) → Result::Ok" do
      result = build_handler(args: %w[sound], raw: "/config sound").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    {
      "on"       => true,
      "off"      => false,
      "true"     => true,
      "false"    => false,
      "enable"   => true,
      "disable"  => false,
      "enabled"  => true,
      "disabled" => false
    }.each do |value, expected_bool|
      it "/config sound #{value} → Result::Ok (writes sound_enabled=#{expected_bool})" do
        expect(AppSetting).to receive(:sound_enabled=).with(expected_bool)
        result = build_handler(args: [ "sound", value ], raw: "/config sound #{value}").call
        expect(result).to be_a(Pito::Slash::Result::Ok)
      end
    end

    %w[maybe yes no 1 0 yep nope flip toggle].each do |invalid|
      it "/config sound #{invalid} → invalid_toggle_value error" do
        result = build_handler(args: [ "sound", invalid ], raw: "/config sound #{invalid}").call
        expect(result).to be_a(Pito::Slash::Result::Error)
        expect(result.message_key).to eq("pito.slash.config.errors.invalid_toggle_value")
        expect(result.message_args[:value]).to eq(invalid)
      end
    end

    it "/config sound on broadcasts a settings-update event" do
      expect(broadcaster).to receive(:broadcast_settings_update)
      build_handler(args: %w[sound on], raw: "/config sound on").call
    end

    it "/config sound (getter) does NOT write sound_enabled" do
      expect(AppSetting).not_to receive(:sound_enabled=)
      build_handler(args: %w[sound], raw: "/config sound").call
    end
  end
  # ── Google credential provider ─────────────────────────────────────────────
  describe "google provider" do
    it "/config google (getter, no kwargs) → Result::Ok with table_rows array" do
      result = build_handler(args: %w[google], raw: "/config google").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      rows = result.events.first[:payload][:table_rows]
      expect(rows).to be_an(Array).and be_present
      expect(rows.first).to include(:key, :value, :value_class)
    end

    # ── individual kwarg setters ──────────────────────────────────────────────
    it "/config google client_id=x → Result::Ok; calls singleton_row.update! with google_oauth_client_id" do
      expect(singleton_row).to receive(:update!).with(google_oauth_client_id: "my-id")
      result = build_handler(args: %w[google], kwargs: { client_id: "my-id" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.config.updated")
    end

    it "/config google client_secret=x → Result::Ok; calls singleton_row.update! with google_oauth_client_secret" do
      expect(singleton_row).to receive(:update!).with(google_oauth_client_secret: "my-secret")
      result = build_handler(args: %w[google], kwargs: { client_secret: "my-secret" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config google redirect_uri=<url> → Result::Ok; calls AppSetting.google_oauth_redirect_uri=" do
      expect(AppSetting).to receive(:google_oauth_redirect_uri=).with("http://localhost:3000/cb")
      result = build_handler(args: %w[google], kwargs: { redirect_uri: "http://localhost:3000/cb" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config google api_key=x → Result::Ok; calls AppSetting.google_api_key=" do
      expect(AppSetting).to receive(:google_api_key=).with("my-api-key")
      result = build_handler(args: %w[google], kwargs: { api_key: "my-api-key" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    # ── multi-kwarg setters ───────────────────────────────────────────────────
    it "/config google client_id=x client_secret=y → Result::Ok" do
      result = build_handler(args: %w[google], kwargs: { client_id: "a", client_secret: "b" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config google redirect_uri=x api_key=y → Result::Ok" do
      result = build_handler(args: %w[google], kwargs: { redirect_uri: "http://localhost/cb", api_key: "k" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config google client_id=a client_secret=b redirect_uri=c api_key=d (all kwargs) → Result::Ok" do
      result = build_handler(
        args: %w[google],
        kwargs: { client_id: "a", client_secret: "b", redirect_uri: "http://x/cb", api_key: "k" }
      ).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "setter calls Pito::Credentials.invalidate! to flush the cache" do
      expect(Pito::Credentials).to receive(:invalidate!)
      build_handler(args: %w[google], kwargs: { client_id: "x" }).call
    end

    # ── unknown kwargs ────────────────────────────────────────────────────────
    it "/config google unknown_key=x → unknown_keys error" do
      result = build_handler(args: %w[google], kwargs: { unknown_key: "x" }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
    end

    it "/config google client_id=x bad_key=y (mixed valid/invalid) → unknown_keys error" do
      result = build_handler(args: %w[google], kwargs: { client_id: "x", bad_key: "y" }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
    end

    it "/config google voyage_key=x → unknown_keys error (cross-provider kwarg rejected)" do
      result = build_handler(args: %w[google], kwargs: { voyage_key: "x" }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
    end
  end

  # ── Voyage credential provider ────────────────────────────────────────────
  describe "voyage provider" do
    it "/config voyage (getter, no kwargs) → Result::Ok with table_rows" do
      result = build_handler(args: %w[voyage], raw: "/config voyage").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      rows = result.events.first[:payload][:table_rows]
      expect(rows).to be_an(Array).and be_present
    end

    it "/config voyage api_key=x → Result::Ok; calls singleton_row.update! with voyage_api_key" do
      expect(singleton_row).to receive(:update!).with(voyage_api_key: "voyage-key")
      result = build_handler(args: %w[voyage], kwargs: { api_key: "voyage-key" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.config.updated")
    end

    %w[client_id client_secret redirect_uri slack discord unknown_key].each do |bad_kwarg|
      it "/config voyage #{bad_kwarg}=x → unknown_keys error (only api_key accepted)" do
        result = build_handler(args: %w[voyage], kwargs: { bad_kwarg.to_sym => "x" }).call
        expect(result).to be_a(Pito::Slash::Result::Error)
        expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
      end
    end
  end

  # ── IGDB credential provider ───────────────────────────────────────────────
  describe "igdb provider" do
    it "/config igdb (getter, no kwargs) → Result::Ok with table_rows" do
      result = build_handler(args: %w[igdb], raw: "/config igdb").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      rows = result.events.first[:payload][:table_rows]
      expect(rows).to be_an(Array).and be_present
    end

    it "/config igdb client_id=x → Result::Ok; calls AppSetting.igdb_client_id=" do
      expect(AppSetting).to receive(:igdb_client_id=).with("igdb-id")
      result = build_handler(args: %w[igdb], kwargs: { client_id: "igdb-id" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config igdb client_secret=x → Result::Ok; calls AppSetting.igdb_client_secret=" do
      expect(AppSetting).to receive(:igdb_client_secret=).with("igdb-secret")
      result = build_handler(args: %w[igdb], kwargs: { client_secret: "igdb-secret" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config igdb client_id=x client_secret=y (both kwargs) → Result::Ok" do
      result = build_handler(args: %w[igdb], kwargs: { client_id: "a", client_secret: "b" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    %w[api_key redirect_uri slack discord unknown_key voyage_key].each do |bad_kwarg|
      it "/config igdb #{bad_kwarg}=x → unknown_keys error" do
        result = build_handler(args: %w[igdb], kwargs: { bad_kwarg.to_sym => "x" }).call
        expect(result).to be_a(Pito::Slash::Result::Error)
        expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
      end
    end
  end

  # ── Webhook credential provider ───────────────────────────────────────────
  describe "webhook provider" do
    it "/config webhook (getter, no kwargs) → Result::Ok with table_rows" do
      result = build_handler(args: %w[webhook], raw: "/config webhook").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      rows = result.events.first[:payload][:table_rows]
      expect(rows).to be_an(Array).and be_present
    end

    it "/config webhook slack=<url> → Result::Ok; calls AppSetting.slack_webhook_url=" do
      expect(AppSetting).to receive(:slack_webhook_url=).with("https://hooks.slack.com/x")
      result = build_handler(args: %w[webhook], kwargs: { slack: "https://hooks.slack.com/x" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config webhook discord=<url> → Result::Ok; calls AppSetting.discord_webhook_url=" do
      expect(AppSetting).to receive(:discord_webhook_url=).with("https://discord.com/webhook/x")
      result = build_handler(args: %w[webhook], kwargs: { discord: "https://discord.com/webhook/x" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config webhook slack=x discord=y (both kwargs) → Result::Ok" do
      result = build_handler(
        args: %w[webhook],
        kwargs: { slack: "https://hooks.slack.com/x", discord: "https://discord.com/x" }
      ).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    %w[api_key client_id client_secret redirect_uri unknown_key].each do |bad_kwarg|
      it "/config webhook #{bad_kwarg}=x → unknown_keys error" do
        result = build_handler(args: %w[webhook], kwargs: { bad_kwarg.to_sym => "x" }).call
        expect(result).to be_a(Pito::Slash::Result::Error)
        expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
      end
    end
  end

  # ── Me provider ──────────────────────────────────────────────────────────────
  describe "me provider" do
  end

  # ── Timezone provider ─────────────────────────────────────────────────────────
  #
  # Two recognized forms:
  #   bare:  /config timezone <City>        — positional arg form
  #   kv:    /config timezone=<City>        — kwarg form
  # Both share the same handler path (timezone_command? fires before provider check).
  describe "timezone provider" do
    # ── getter ──────────────────────────────────────────────────────────────────
    it "/config timezone (getter, no arg, no kwarg) → Result::Ok with current zone" do
      result = build_handler(args: %w[timezone], raw: "/config timezone").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config timezone (getter) does NOT call AppSetting.timezone=" do
      expect(AppSetting).not_to receive(:timezone=)
      build_handler(args: %w[timezone], raw: "/config timezone").call
    end

    # ── bare positional setter ──────────────────────────────────────────────────
    [
      [ "Madrid", "Europe/Madrid" ],
      [ "Tokyo",  "Asia/Tokyo" ],
      [ "London", "Europe/London" ],
      [ "Paris",  "Europe/Paris" ]
    ].each do |city, expected_iana|
      it "/config timezone #{city} → Result::Ok; resolves to #{expected_iana}" do
        expect(AppSetting).to receive(:timezone=).with(expected_iana)
        result = build_handler(args: [ "timezone", city ], raw: "/config timezone #{city}").call
        expect(result).to be_a(Pito::Slash::Result::Ok)
      end
    end

    # ── kv setter ─────────────────────────────────────────────────────────────
    it "/config timezone=Madrid (kv setter) → Result::Ok" do
      result = build_handler(kwargs: { timezone: "Madrid" }, raw: "/config timezone=Madrid").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config timezone=Tokyo (kv setter) → Result::Ok" do
      result = build_handler(kwargs: { timezone: "Tokyo" }, raw: "/config timezone=Tokyo").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "/config timezone=London (kv setter) → Result::Ok" do
      result = build_handler(kwargs: { timezone: "London" }, raw: "/config timezone=London").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    # ── error: unresolvable city ────────────────────────────────────────────────
    it "/config timezone Nowhereville → unknown_timezone error" do
      result = build_handler(args: %w[timezone Nowhereville]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_timezone")
      expect(result.message_args[:city]).to eq("Nowhereville")
    end

    it "/config timezone=Bogus (kv, unresolvable) → unknown_timezone error" do
      result = build_handler(kwargs: { timezone: "Bogus" }, raw: "/config timezone=Bogus").call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_timezone")
    end

    it "/config timezone XyZZy → unknown_timezone error" do
      result = build_handler(args: %w[timezone XyZZy]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_timezone")
    end

    # ── blank kv value → getter path ────────────────────────────────────────────
    it "/config timezone=   (blank value) → Result::Ok (blank city → getter path)" do
      # timezone_value strips → blank? → show_timezone (getter, not setter)
      result = build_handler(kwargs: { timezone: "   " }, raw: "/config timezone=   ").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end
  end
end
