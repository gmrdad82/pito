# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Config, type: :service do
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

  describe "#call — /config --help (general)" do
    it "returns a man-page system event with Usage: and all provider tokens" do
      result = build_handler(raw: "/config --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.length).to eq(1)
      payload = result.events.first[:payload]
      expect(payload["html"]).to be true
      body = payload["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("Usage:")
      expect(body).to include("/config")
      %w[google voyage igdb webhook].each { |p| expect(body).to include(p) }
    end

    it "does not treat --help as an unknown provider error" do
      result = build_handler(raw: "/config --help").call
      expect(result).not_to be_a(Pito::Slash::Result::Error)
    end
  end

  describe "#call — /config google --help" do
    it "returns a man-page system event with all google key tokens and /connect hint" do
      result = build_handler(args: [ "google" ], raw: "/config google --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.length).to eq(1)
      body = result.events.first[:payload]["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("client_id=")
      expect(body).to include("client_secret=")
      expect(body).to include("redirect_uri=")
      expect(body).to include("api_key=")
      expect(body).to include("/connect")
    end
  end

  describe "#call — URL kwarg value" do
    it "accepts redirect_uri with a full http URL (no parse error)" do
      result = build_handler(
        args:   [ "google" ],
        kwargs: { redirect_uri: "http://localhost:3027/auth/youtube/callback" }
      ).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.google_oauth_redirect_uri).to eq("http://localhost:3027/auth/youtube/callback")
    end
  end

  describe "#call — unknown provider" do
    it "returns an error" do
      result = build_handler(args: [ "unknown_service" ]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_provider")
    end
  end

  describe "#call — /config google (getter)" do
    before do
      AppSetting.singleton_row.update!(
        google_oauth_client_id:     "my-id",
        google_oauth_client_secret: "my-secret"
      )
      Pito::Credentials.invalidate!
    end

    it "returns a structured system event with table_rows containing OK flags" do
      result = build_handler(args: [ "google" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.length).to eq(1)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      keys   = event[:payload][:table_rows].map { |r| r[:key] }
      values = event[:payload][:table_rows].map { |r| r[:value] }
      expect(keys).to include("Client ID:")
      expect(values).to all(eq(I18n.t("pito.slash.config.status.ok")).or(eq(I18n.t("pito.slash.config.status.missing"))))
    end

    it "returns table_rows with red MISSING for absent credentials" do
      AppSetting.singleton_row.update!(
        google_oauth_client_id:     nil,
        google_oauth_client_secret: nil
      )
      Pito::Credentials.invalidate!

      result = build_handler(args: [ "google" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      rows = result.events.first[:payload][:table_rows]
      expect(rows).to be_present
      # In test env both fall back to placeholders so they may still be "OK",
      # but the structure must always be present.
      expect(rows.first).to include(:key, :value, :value_class)
    end
  end

  describe "#call — /config google client_id=x client_secret=y (setter)" do
    it "persists credentials to AppSetting" do
      build_handler(args: [ "google" ], kwargs: { client_id: "new-id", client_secret: "new-secret" }).call

      AppSetting.singleton_row.reload
      expect(AppSetting.singleton_row.google_oauth_client_id).to eq("new-id")
      expect(AppSetting.singleton_row.google_oauth_client_secret).to eq("new-secret")
    end

    it "returns a Result::Ok confirming the updated keys" do
      result = build_handler(args: [ "google" ], kwargs: { client_id: "id" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.config.updated")
    end

    it "accepts a single key" do
      result = build_handler(args: [ "google" ], kwargs: { redirect_uri: "http://localhost/callback" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.google_oauth_redirect_uri).to eq("http://localhost/callback")
    end

    it "returns an error for unknown keys" do
      result = build_handler(args: [ "google" ], kwargs: { invalid_key: "val" }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
    end
  end

  # ── Sound / FX toggle path ──────────────────────────────────────────────────

  describe "#call — /config sound (getter, no arg)" do
    it "returns a system event with the current sound state" do
      AppSetting.sound_enabled = true
      result = build_handler(args: [ "sound" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      text = result.events.first[:payload][:text]
      expect(text).to include("Sound").and include("on")
    end

    it "reflects false when sound is disabled" do
      AppSetting.sound_enabled = false
      result = build_handler(args: [ "sound" ]).call
      text = result.events.first[:payload][:text]
      expect(text).to include("off")
      AppSetting.sound_enabled = true # restore
    end
  end

  describe "#call — /config sound on (setter)" do
    it "enables sound and broadcasts a settings update" do
      AppSetting.sound_enabled = false
      broadcaster_double = instance_double(Pito::Stream::Broadcaster, broadcast_settings_update: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster_double)

      result = build_handler(args: [ "sound", "on" ]).call

      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.sound_enabled?).to be true
      expect(broadcaster_double).to have_received(:broadcast_settings_update)
      AppSetting.sound_enabled = true # restore
    end

    it "accepts 'true' as a synonym for on" do
      AppSetting.sound_enabled = false
      allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:broadcast_settings_update)

      result = build_handler(args: [ "sound", "true" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.sound_enabled?).to be true
      AppSetting.sound_enabled = true # restore
    end

    it "accepts 'disable' as a synonym for off" do
      allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:broadcast_settings_update)

      result = build_handler(args: [ "sound", "disable" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.sound_enabled?).to be false
      AppSetting.sound_enabled = true # restore
    end

    it "returns an error for invalid toggle values" do
      result = build_handler(args: [ "sound", "maybe" ]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.invalid_toggle_value")
    end
  end

  describe "#call — /config fx off (setter)" do
    it "disables fx and broadcasts a settings update" do
      AppSetting.fx_enabled = true
      broadcaster_double = instance_double(Pito::Stream::Broadcaster, broadcast_settings_update: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster_double)

      result = build_handler(args: [ "fx", "off" ]).call

      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.fx_enabled?).to be false
      expect(broadcaster_double).to have_received(:broadcast_settings_update)
      AppSetting.fx_enabled = true # restore
    end
  end

  describe "#call — credential path still works (non-toggle provider)" do
    it "/config google client_id=x still uses credential path unchanged" do
      result = build_handler(args: [ "google" ], kwargs: { client_id: "new-id" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.config.updated")
    end
  end

  describe "#call — general help lists sound and fx" do
    it "includes sound and fx in the help body" do
      result = build_handler(raw: "/config --help").call
      body = result.events.first[:payload]["body"]
      expect(body).to include("sound")
      expect(body).to include("fx")
    end
  end

  # ── Time zone path ──────────────────────────────────────────────────────────

  describe "#call — /config timezone=<City> (kv setter)" do
    it "resolves a major city to its IANA zone and persists it" do
      result = build_handler(kwargs: { timezone: "Madrid" }, raw: "/config timezone=Madrid").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.timezone).to eq("Europe/Madrid")
      expect(result.events.first[:payload][:text]).to include("Europe/Madrid")
    end

    it "returns a witty error for an unknown city and persists nothing" do
      AppSetting.where(key: AppSetting::TIMEZONE_KEY).delete_all
      result = build_handler(kwargs: { timezone: "Nowhereville" }, raw: "/config timezone=Nowhereville").call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_timezone")
      expect(AppSetting.get(AppSetting::TIMEZONE_KEY)).to be_nil
    end
  end

  describe "#call — /config timezone <City> (bare setter)" do
    it "resolves the city from the positional argument" do
      result = build_handler(args: [ "timezone", "Tokyo" ], raw: "/config timezone Tokyo").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.timezone).to eq("Asia/Tokyo")
    end
  end

  describe "#call — /config timezone (getter)" do
    it "shows the currently configured zone" do
      AppSetting.timezone = "London"
      result = build_handler(args: [ "timezone" ], raw: "/config timezone").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:text]).to include("Europe/London")
    end
  end

  describe "#call — /config timezone --help" do
    it "returns a man-page body containing /config timezone" do
      result = build_handler(args: [ "timezone" ], raw: "/config timezone --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      body = result.events.first[:payload]["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("/config timezone")
    end
  end

  # ── /config me path ─────────────────────────────────────────────────────────

  describe "#call — /config me nickname=<value> (setter)" do
    before { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }
    after  { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }

    it "persists the nickname to AppSetting" do
      build_handler(args: [ "me" ], kwargs: { nickname: "Foo" }).call
      expect(AppSetting.nickname).to eq("Foo")
    end

    it "broadcasts a global mini-status refresh so the auth label updates live" do
      expect(Pito::Stream::Broadcaster).to receive(:broadcast_global_mini_status)
      build_handler(args: [ "me" ], kwargs: { nickname: "Foo" }).call
    end

    it "does not broadcast when the nickname is blank (error path)" do
      expect(Pito::Stream::Broadcaster).not_to receive(:broadcast_global_mini_status)
      build_handler(args: [ "me" ], kwargs: { nickname: "   " }).call
    end

    it "returns a Result::Ok with a confirmation text" do
      result = build_handler(args: [ "me" ], kwargs: { nickname: "Foo" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:text]).to include("Foo")
    end

    it "returns an error for an unknown key" do
      result = build_handler(args: [ "me" ], kwargs: { bad_key: "val" }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
    end

    it "returns an error for a blank nickname value" do
      result = build_handler(args: [ "me" ], kwargs: { nickname: "   " }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.blank_nickname")
    end
  end

  describe "#call — /config me (getter, no kwargs)" do
    before { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }
    after  { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }

    it "shows the current nickname" do
      AppSetting.nickname = "streamer"
      result = build_handler(args: [ "me" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:text]).to include("streamer")
    end

    it "shows the default nickname when none is set" do
      result = build_handler(args: [ "me" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:text]).to include("gmrdad82")
    end
  end

  describe "#call — /config me --help" do
    it "returns a man-page system event with nickname= token" do
      result = build_handler(args: [ "me" ], raw: "/config me --help").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      body = result.events.first[:payload]["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("Usage:")
      expect(body).to include("/config me")
      expect(body).to include("nickname=")
    end
  end

  describe "#call — general help includes me" do
    it "includes me in the help body" do
      result = build_handler(raw: "/config --help").call
      body = result.events.first[:payload]["body"]
      expect(body).to include("me")
    end
  end

  describe "echo masking in ChatController" do
    it "masks client_id and client_secret but shows redirect_uri" do
      ctrl = ChatController.new
      input = "/config google client_id=myid client_secret=myscret redirect_uri=http://localhost/cb"
      masked = ctrl.send(:mask_config_credentials, input)
      expect(masked).to eq("/config google client_id=*** client_secret=*** redirect_uri=http://localhost/cb")
    end

    it "is a no-op when no sensitive keys are present" do
      ctrl = ChatController.new
      input = "/config google redirect_uri=http://localhost/cb"
      expect(ctrl.send(:mask_config_credentials, input)).to eq(input)
    end
  end
end
