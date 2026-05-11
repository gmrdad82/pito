require "rails_helper"

RSpec.describe AppSetting, type: :model do
  subject { build(:app_setting) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:key) }
    it { is_expected.to validate_uniqueness_of(:key).case_insensitive }
    it { is_expected.to validate_presence_of(:value) }
  end

  describe "encryption" do
    it "encrypts the value column" do
      setting = create(:app_setting, key: "secret_key", value: "secret_value")
      raw = AppSetting.connection.select_one(
        "SELECT value FROM app_settings WHERE id = #{setting.id}"
      )["value"]
      expect(raw).not_to eq("secret_value")
    end

    # Phase 4 §3.5 (Phase B revamp, 2026-05-04) — voyage_api_key is encrypted
    # via Active Record Encryption (probabilistic, not deterministic). The
    # plaintext must never round-trip through raw SQL.
    it "encrypts the voyage_api_key column" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes",
        value: "5",
        voyage_api_key: "vk_plaintext_secret"
      )
      raw = AppSetting.connection.select_one(
        "SELECT voyage_api_key FROM app_settings WHERE id = #{setting.id}"
      )["voyage_api_key"]
      expect(raw).to be_present
      expect(raw).not_to eq("vk_plaintext_secret")
      expect(raw).not_to include("vk_plaintext_secret")
    end

    it "round-trips voyage_api_key plaintext via the model accessor" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes",
        value: "5",
        voyage_api_key: "vk_round_trip"
      )
      expect(setting.reload.voyage_api_key).to eq("vk_round_trip")
    end

    # 2026-05-11 — YouTube credentials moved out of
    # `Rails.application.credentials.google_oauth` into the singleton
    # AppSetting row. Sensitive fields (`youtube_api_key`,
    # `youtube_client_secret`) ride on the same Active Record
    # Encryption pattern as `voyage_api_key`: probabilistic, not
    # deterministic. The non-sensitive fields (`youtube_client_id`,
    # `youtube_redirect_uri`) stay plaintext so the UI can echo them
    # back in input placeholders.
    it "encrypts the youtube_api_key column" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes",
        value: "5",
        youtube_api_key: "AIzaSyFAKE_plaintext_42"
      )
      raw = AppSetting.connection.select_one(
        "SELECT youtube_api_key FROM app_settings WHERE id = #{setting.id}"
      )["youtube_api_key"]
      expect(raw).to be_present
      expect(raw).not_to eq("AIzaSyFAKE_plaintext_42")
      expect(raw).not_to include("AIzaSyFAKE_plaintext_42")
    end

    it "encrypts the youtube_client_secret column" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes",
        value: "5",
        youtube_client_secret: "GOCSPX-FAKE_plaintext_42"
      )
      raw = AppSetting.connection.select_one(
        "SELECT youtube_client_secret FROM app_settings WHERE id = #{setting.id}"
      )["youtube_client_secret"]
      expect(raw).to be_present
      expect(raw).not_to eq("GOCSPX-FAKE_plaintext_42")
      expect(raw).not_to include("GOCSPX-FAKE_plaintext_42")
    end

    it "round-trips youtube_api_key plaintext via the model accessor" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes",
        value: "5",
        youtube_api_key: "round_trip_api_key"
      )
      expect(setting.reload.youtube_api_key).to eq("round_trip_api_key")
    end

    it "round-trips youtube_client_secret plaintext via the model accessor" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes",
        value: "5",
        youtube_client_secret: "round_trip_client_secret"
      )
      expect(setting.reload.youtube_client_secret).to eq("round_trip_client_secret")
    end

    it "stores youtube_client_id in plaintext (public-ish; not encrypted)" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes",
        value: "5",
        youtube_client_id: "123-abc.apps.googleusercontent.com"
      )
      raw = AppSetting.connection.select_one(
        "SELECT youtube_client_id FROM app_settings WHERE id = #{setting.id}"
      )["youtube_client_id"]
      expect(raw).to eq("123-abc.apps.googleusercontent.com")
    end

    it "stores youtube_redirect_uri in plaintext (public callback URL; not encrypted)" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes",
        value: "5",
        youtube_redirect_uri: "https://example.test/auth/google/callback"
      )
      raw = AppSetting.connection.select_one(
        "SELECT youtube_redirect_uri FROM app_settings WHERE id = #{setting.id}"
      )["youtube_redirect_uri"]
      expect(raw).to eq("https://example.test/auth/google/callback")
    end
  end

  describe ".get" do
    it "returns the value for an existing key" do
      create(:app_setting, key: "youtube_client_id", value: "abc123")
      expect(AppSetting.get("youtube_client_id")).to eq("abc123")
    end

    it "returns nil for a missing key" do
      expect(AppSetting.get("nonexistent")).to be_nil
    end
  end

  describe ".set" do
    it "creates a new setting" do
      expect { AppSetting.set("new_key", "new_value") }.to change(AppSetting, :count).by(1)
      expect(AppSetting.get("new_key")).to eq("new_value")
    end

    it "updates an existing setting" do
      create(:app_setting, key: "existing", value: "old")
      expect { AppSetting.set("existing", "new") }.not_to change(AppSetting, :count)
      expect(AppSetting.get("existing")).to eq("new")
    end
  end

  # Phase 4 §3.5 (Phase B revamp, 2026-05-04) — defaults on a freshly migrated
  # app_settings row. `voyage_api_key` is nil; `voyage_index_project_notes`
  # is false (NOT NULL with default false at the schema level).
  describe "voyage column defaults" do
    it "voyage_api_key is nil on a freshly created row" do
      setting = create(:app_setting)
      expect(setting.voyage_api_key).to be_nil
    end

    it "voyage_index_project_notes is false on a freshly created row" do
      setting = create(:app_setting)
      expect(setting.voyage_index_project_notes).to be(false)
    end
  end

  describe ".voyage_configured?" do
    it "returns false when no AppSetting row exists" do
      AppSetting.delete_all
      expect(AppSetting.voyage_configured?).to be(false)
    end

    it "returns false when the key is nil" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5")
      expect(AppSetting.voyage_configured?).to be(false)
    end

    it "returns false when the key is blank string" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5", voyage_api_key: "")
      expect(AppSetting.voyage_configured?).to be(false)
    end

    it "returns false when the key is whitespace-only" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5", voyage_api_key: "   ")
      expect(AppSetting.voyage_configured?).to be(false)
    end

    it "returns true when the key is a non-blank string" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5", voyage_api_key: "vk_something")
      expect(AppSetting.voyage_configured?).to be(true)
    end
  end

  # 2026-05-11 — keyboard-navigation master toggle. The column is a
  # NOT-NULL boolean with `default: true` so a freshly migrated row
  # starts with the feature enabled. `.keyboard_navigation_enabled?`
  # returns `true` when no AppSetting row exists yet (matches the
  # column default); `false` only when an explicit row carries the
  # value `false`. The writer bootstraps a row when the table is
  # empty so the controller never has to nil-check.
  describe "keyboard_navigation_enabled column default" do
    it "is true on a freshly created row" do
      setting = create(:app_setting)
      expect(setting.keyboard_navigation_enabled).to be(true)
    end

    it "is coerced to a Boolean (not an integer or string)" do
      setting = create(:app_setting)
      expect(setting.keyboard_navigation_enabled).to be(true).or be(false)
    end

    it "honours explicit false on insert" do
      setting = create(:app_setting, keyboard_navigation_enabled: false)
      expect(setting.keyboard_navigation_enabled).to be(false)
    end
  end

  describe ".keyboard_navigation_enabled?" do
    it "returns true when no AppSetting row exists" do
      AppSetting.delete_all
      expect(AppSetting.keyboard_navigation_enabled?).to be(true)
    end

    it "returns true when the singleton's column is true" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5",
                         keyboard_navigation_enabled: true)
      expect(AppSetting.keyboard_navigation_enabled?).to be(true)
    end

    it "returns false when the singleton's column is false" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5",
                         keyboard_navigation_enabled: false)
      expect(AppSetting.keyboard_navigation_enabled?).to be(false)
    end
  end

  describe ".set_keyboard_navigation_enabled" do
    it "flips the singleton's column" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5")
      AppSetting.set_keyboard_navigation_enabled(false)
      expect(AppSetting.keyboard_navigation_enabled?).to be(false)
      AppSetting.set_keyboard_navigation_enabled(true)
      expect(AppSetting.keyboard_navigation_enabled?).to be(true)
    end

    it "bootstraps a row when the table is empty" do
      AppSetting.delete_all
      expect {
        AppSetting.set_keyboard_navigation_enabled(false)
      }.to change(AppSetting, :count).by(1)
      expect(AppSetting.keyboard_navigation_enabled?).to be(false)
    end
  end

  # 2026-05-11 — YouTube credential accessors + the
  # `youtube_configured?` predicate.
  describe ".youtube_configured?" do
    before { AppSetting.delete_all }

    it "returns false when no AppSetting row exists" do
      expect(AppSetting.youtube_configured?).to be(false)
    end

    it "returns false when only one of the three required fields is set" do
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_api_key: "k")
      expect(AppSetting.youtube_configured?).to be(false)
    end

    it "returns false when two of the three required fields are set" do
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_api_key: "k",
                         youtube_client_id: "id")
      expect(AppSetting.youtube_configured?).to be(false)
    end

    it "returns true when all three required fields are non-blank" do
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_api_key: "k",
                         youtube_client_id: "id",
                         youtube_client_secret: "s")
      expect(AppSetting.youtube_configured?).to be(true)
    end

    it "ignores the redirect_uri (it's optional)" do
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_api_key: "k",
                         youtube_client_id: "id",
                         youtube_client_secret: "s")
      expect(AppSetting.youtube_configured?).to be(true)
      # Set the redirect URI: still true.
      AppSetting.first.update!(youtube_redirect_uri: "https://x.test/cb")
      expect(AppSetting.youtube_configured?).to be(true)
    end

    it "treats whitespace-only values as blank" do
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_api_key: "   ",
                         youtube_client_id: "id",
                         youtube_client_secret: "s")
      expect(AppSetting.youtube_configured?).to be(false)
    end
  end

  describe ".youtube_api_key / .youtube_client_id / .youtube_client_secret / .youtube_redirect_uri" do
    before { AppSetting.delete_all }

    it "returns nil for every accessor when no row exists" do
      expect(AppSetting.youtube_api_key).to be_nil
      expect(AppSetting.youtube_client_id).to be_nil
      expect(AppSetting.youtube_client_secret).to be_nil
      expect(AppSetting.youtube_redirect_uri).to be_nil
    end

    it "returns the singleton's value when a row exists" do
      AppSetting.create!(
        key: "max_panes", value: "5",
        youtube_api_key:       "api",
        youtube_client_id:     "id",
        youtube_client_secret: "sec",
        youtube_redirect_uri:  "https://x.test/cb"
      )
      expect(AppSetting.youtube_api_key).to       eq("api")
      expect(AppSetting.youtube_client_id).to     eq("id")
      expect(AppSetting.youtube_client_secret).to eq("sec")
      expect(AppSetting.youtube_redirect_uri).to  eq("https://x.test/cb")
    end
  end

  describe ".voyage_indexing_project_notes?" do
    it "returns false when no AppSetting row exists" do
      AppSetting.delete_all
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
    end

    it "returns the singleton's column value when the row exists" do
      AppSetting.delete_all
      AppSetting.create!(
        key: "max_panes", value: "5",
        voyage_api_key: "vk", voyage_index_project_notes: true
      )
      expect(AppSetting.voyage_indexing_project_notes?).to be(true)
    end

    it "returns false when the singleton's column is false" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5", voyage_index_project_notes: false)
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
    end
  end

  # Phase 16 §1 — Notifications data model + delivery channels.
  #
  # The two webhook delivery toggles AND with the `Rails.application.credentials`
  # `notifications.{discord,slack}_webhook_url` keys. Both must be present
  # AND non-blank for the helper to return true.
  describe ".discord_delivery_enabled?" do
    let(:url) { "https://discord.com/api/webhooks/123/abc" }

    before { AppSetting.delete_all }

    it "returns false when no AppSetting row exists" do
      expect(AppSetting.discord_delivery_enabled?).to be(false)
    end

    it "returns true when discord_enabled = true AND credentials carry a non-blank URL" do
      AppSetting.create!(key: "max_panes", value: "5", discord_enabled: true)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :discord_webhook_url).and_return(url)
      expect(AppSetting.discord_delivery_enabled?).to be(true)
    end

    it "returns false when discord_enabled = false, regardless of URL" do
      AppSetting.create!(key: "max_panes", value: "5", discord_enabled: false)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :discord_webhook_url).and_return(url)
      expect(AppSetting.discord_delivery_enabled?).to be(false)
    end

    it "returns false when the URL is blank, regardless of the flag" do
      AppSetting.create!(key: "max_panes", value: "5", discord_enabled: true)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :discord_webhook_url).and_return("")
      expect(AppSetting.discord_delivery_enabled?).to be(false)
    end

    it "returns false when the URL key is missing" do
      AppSetting.create!(key: "max_panes", value: "5", discord_enabled: true)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :discord_webhook_url).and_return(nil)
      expect(AppSetting.discord_delivery_enabled?).to be(false)
    end

    it "returns false when the URL is whitespace-only" do
      AppSetting.create!(key: "max_panes", value: "5", discord_enabled: true)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :discord_webhook_url).and_return("   ")
      expect(AppSetting.discord_delivery_enabled?).to be(false)
    end
  end

  describe ".slack_delivery_enabled?" do
    let(:url) { "https://hooks.slack.com/services/abc/def" }

    before { AppSetting.delete_all }

    it "returns false when no AppSetting row exists" do
      expect(AppSetting.slack_delivery_enabled?).to be(false)
    end

    it "returns true when slack_enabled = true AND credentials carry a non-blank URL" do
      AppSetting.create!(key: "max_panes", value: "5", slack_enabled: true)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :slack_webhook_url).and_return(url)
      expect(AppSetting.slack_delivery_enabled?).to be(true)
    end

    it "returns false when slack_enabled = false, regardless of URL" do
      AppSetting.create!(key: "max_panes", value: "5", slack_enabled: false)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :slack_webhook_url).and_return(url)
      expect(AppSetting.slack_delivery_enabled?).to be(false)
    end

    it "returns false when the URL is blank, regardless of the flag" do
      AppSetting.create!(key: "max_panes", value: "5", slack_enabled: true)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :slack_webhook_url).and_return("")
      expect(AppSetting.slack_delivery_enabled?).to be(false)
    end

    it "returns false when the URL key is missing" do
      AppSetting.create!(key: "max_panes", value: "5", slack_enabled: true)
      allow(Rails.application.credentials).to receive(:dig).with(:notifications, :slack_webhook_url).and_return(nil)
      expect(AppSetting.slack_delivery_enabled?).to be(false)
    end
  end

  # Phase 4 §3.5 (Phase B revamp, 2026-05-04) — model validation guards the
  # "flag on, key blank" combo from both directions: flipping a flag true
  # without a key, and clearing the key while a flag is true. Both fail
  # with the same documented error message.
  describe "voyage_target_flags_require_key validation" do
    let(:error_message) { "Voyage API key required to enable project-notes indexing." }

    it "rejects flipping voyage_index_project_notes to true without a key" do
      AppSetting.delete_all
      setting = AppSetting.create!(key: "max_panes", value: "5")
      setting.voyage_index_project_notes = true
      expect(setting).not_to be_valid
      expect(setting.errors[:voyage_api_key]).to include(error_message)
    end

    it "succeeds when the key is set first, then the flag is flipped" do
      AppSetting.delete_all
      setting = AppSetting.create!(key: "max_panes", value: "5", voyage_api_key: "vk")
      setting.voyage_index_project_notes = true
      expect(setting).to be_valid
      expect { setting.save! }.not_to raise_error
    end

    it "rejects clearing the key while voyage_index_project_notes is true" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes", value: "5",
        voyage_api_key: "vk", voyage_index_project_notes: true
      )
      setting.voyage_api_key = nil
      expect(setting).not_to be_valid
      expect(setting.errors[:voyage_api_key]).to include(error_message)
    end

    it "allows clearing the key after flipping the flag back to false" do
      AppSetting.delete_all
      setting = AppSetting.create!(
        key: "max_panes", value: "5",
        voyage_api_key: "vk", voyage_index_project_notes: true
      )
      setting.voyage_index_project_notes = false
      expect(setting.save).to be(true)
      setting.voyage_api_key = nil
      expect(setting.save).to be(true)
    end

    it "is idempotent across repeated flag flips when the key is present" do
      AppSetting.delete_all
      setting = AppSetting.create!(key: "max_panes", value: "5", voyage_api_key: "vk")
      setting.update!(voyage_index_project_notes: true)
      expect(AppSetting.voyage_indexing_project_notes?).to be(true)
      setting.update!(voyage_index_project_notes: false)
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
    end
  end
end
