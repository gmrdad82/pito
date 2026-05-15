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
  end

  # Phase 29 — Unit A1. The seven secret-bearing / orphaned columns
  # that drifted onto the singleton during alpha / beta-1 are dropped:
  # the YouTube OAuth credentials, the Voyage API key, and the orphaned
  # Slack / Discord `*_enabled` gate columns. This is the
  # dead-columns-are-gone regression spec — a leftover read would raise
  # `NoMethodError`, so the assertions pin both the schema and the
  # model accessor surface.
  describe "dropped credential / dead columns (Unit A1)" do
    let(:dropped_columns) do
      %w[
        voyage_api_key
        youtube_api_key
        youtube_client_id
        youtube_client_secret
        youtube_redirect_uri
        slack_enabled
        discord_enabled
      ]
    end

    it "app_settings has none of the seven dropped columns" do
      expect(AppSetting.column_names).not_to include(*dropped_columns)
    end

    it "the model no longer responds to the dropped YouTube class accessors" do
      expect(AppSetting).not_to respond_to(:youtube_api_key)
      expect(AppSetting).not_to respond_to(:youtube_client_id)
      expect(AppSetting).not_to respond_to(:youtube_client_secret)
      expect(AppSetting).not_to respond_to(:youtube_redirect_uri)
      expect(AppSetting).not_to respond_to(:youtube_configured?)
    end

    it "an instance no longer responds to the dropped column accessors" do
      setting = create(:app_setting)
      dropped_columns.each do |column|
        expect(setting).not_to respond_to(column)
      end
    end
  end

  describe ".get" do
    it "returns the value for an existing key" do
      create(:app_setting, key: "max_panes", value: "abc123")
      expect(AppSetting.get("max_panes")).to eq("abc123")
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

  # Phase 29 — Unit A1. `voyage_index_project_notes` (the non-secret
  # runtime flag) STAYS on the singleton; only the `voyage_api_key`
  # secret moved to credentials.
  describe "voyage_index_project_notes column default" do
    it "voyage_index_project_notes is false on a freshly created row" do
      setting = create(:app_setting)
      expect(setting.voyage_index_project_notes).to be(false)
    end
  end

  # Phase 29 — Unit A1. `voyage_configured?` now reflects the
  # `Rails.application.credentials.voyage.api_key` presence (flat block,
  # shared across environments), NOT a column on this table.
  describe ".voyage_configured?" do
    it "returns true when the credentials carry a non-blank Voyage key" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return("vk_from_creds")
      expect(AppSetting.voyage_configured?).to be(true)
    end

    it "returns false when the credentials key is nil" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return(nil)
      expect(AppSetting.voyage_configured?).to be(false)
    end

    it "returns false when the credentials key is a blank string" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return("")
      expect(AppSetting.voyage_configured?).to be(false)
    end

    it "returns false when the credentials key is whitespace-only" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return("   ")
      expect(AppSetting.voyage_configured?).to be(false)
    end

    it "does not read any AppSetting column" do
      # The `voyage_api_key` column is dropped — a column read would
      # raise. Stub the credentials away and confirm the predicate
      # still answers cleanly from credentials alone.
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return(nil)
      create(:app_setting)
      expect { AppSetting.voyage_configured? }.not_to raise_error
      expect(AppSetting.voyage_configured?).to be(false)
    end
  end

  # 2026-05-11 — keyboard-navigation master toggle. The column is a
  # NOT-NULL boolean with `default: true` so a freshly migrated row
  # starts with the feature enabled.
  describe "keyboard_navigation_enabled column default" do
    it "is true on a freshly created row" do
      setting = create(:app_setting)
      expect(setting.keyboard_navigation_enabled).to be(true)
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

  describe ".voyage_indexing_project_notes?" do
    it "returns false when no AppSetting row exists" do
      AppSetting.delete_all
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
    end

    it "returns the singleton's column value when the row exists" do
      AppSetting.delete_all
      AppSetting.create!(
        key: "max_panes", value: "5", voyage_index_project_notes: true
      )
      expect(AppSetting.voyage_indexing_project_notes?).to be(true)
    end

    it "returns false when the singleton's column is false" do
      AppSetting.delete_all
      AppSetting.create!(key: "max_panes", value: "5", voyage_index_project_notes: false)
      expect(AppSetting.voyage_indexing_project_notes?).to be(false)
    end
  end

  # Phase 29 — Unit A1 (Part 4 delivery bug fix). The Slack / Discord
  # delivery gate is derived ENTIRELY from the
  # `NotificationDeliveryChannel` row for the kind — its existence plus
  # a present `webhook_url` and at least one routing flag set. The
  # orphaned `AppSetting.*_enabled` columns are dropped and never read.
  shared_examples "a delivery-channel gate predicate" do |kind, predicate, valid_url|
    before { AppSetting.delete_all }

    it "returns false when no #{kind} channel row exists" do
      expect(AppSetting.public_send(predicate)).to be(false)
    end

    it "returns false with a channel row that has no routing flag set" do
      NotificationDeliveryChannel.create!(
        kind: kind, webhook_url: valid_url, everything: false, daily_digest: false
      )
      expect(AppSetting.public_send(predicate)).to be(false)
    end

    it "returns false with a channel row whose webhook_url is blank" do
      channel = NotificationDeliveryChannel.new(
        kind: kind, webhook_url: "", everything: true
      )
      channel.save!(validate: false)
      expect(AppSetting.public_send(predicate)).to be(false)
    end

    it "returns true with a channel row that has a webhook_url and `everything` set" do
      NotificationDeliveryChannel.create!(
        kind: kind, webhook_url: valid_url, everything: true
      )
      expect(AppSetting.public_send(predicate)).to be(true)
    end

    it "returns true with a channel row that has a webhook_url and `daily_digest` set" do
      NotificationDeliveryChannel.create!(
        kind: kind, webhook_url: valid_url, daily_digest: true
      )
      expect(AppSetting.public_send(predicate)).to be(true)
    end

    it "does not read any (dropped) AppSetting column" do
      NotificationDeliveryChannel.create!(
        kind: kind, webhook_url: valid_url, everything: true
      )
      # No AppSetting row at all — the predicate must still answer
      # `true` purely from the channel row.
      expect { AppSetting.public_send(predicate) }.not_to raise_error
      expect(AppSetting.public_send(predicate)).to be(true)
    end
  end

  describe ".slack_delivery_enabled?" do
    it_behaves_like "a delivery-channel gate predicate", "slack",
                    :slack_delivery_enabled?,
                    "https://hooks.slack.com/services/T01ABC/B01DEF/abcXYZ123"
  end

  describe ".discord_delivery_enabled?" do
    it_behaves_like "a delivery-channel gate predicate", "discord",
                    :discord_delivery_enabled?,
                    "https://discord.com/api/webhooks/123456789/abcDEF_-ghi"
  end
end
