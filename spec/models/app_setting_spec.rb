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

  # Phase 29 (settings refactor) — the table now carries only
  # `(key, value)` rows. The seven secret-bearing / orphaned columns
  # from earlier waves stay dropped; the three UX columns
  # (`keyboard_navigation_enabled`, `timezone`,
  # `voyage_index_project_notes`) are dropped in this refactor
  # alongside the matching settings panes.
  describe "dropped columns" do
    let(:dropped_columns) do
      %w[
        voyage_api_key
        youtube_api_key
        youtube_client_id
        youtube_client_secret
        youtube_redirect_uri
        slack_enabled
        discord_enabled
        keyboard_navigation_enabled
        timezone
        voyage_index_project_notes
      ]
    end

    it "app_settings has none of the dropped columns" do
      expect(AppSetting.column_names).not_to include(*dropped_columns)
    end

    it "the model no longer responds to the dropped YouTube class accessors" do
      expect(AppSetting).not_to respond_to(:youtube_api_key)
      expect(AppSetting).not_to respond_to(:youtube_client_id)
      expect(AppSetting).not_to respond_to(:youtube_client_secret)
      expect(AppSetting).not_to respond_to(:youtube_redirect_uri)
      expect(AppSetting).not_to respond_to(:youtube_configured?)
    end

    it "the model no longer responds to the dropped keyboard-nav class accessors" do
      expect(AppSetting).not_to respond_to(:keyboard_navigation_enabled?)
      expect(AppSetting).not_to respond_to(:set_keyboard_navigation_enabled)
    end

    it "an instance no longer responds to the dropped column accessors" do
      setting = build_stubbed(:app_setting)
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

  # Phase 29 (settings refactor) — `voyage_configured?` reflects
  # `Rails.application.credentials.voyage.api_key` presence; no DB
  # column survives.
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
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return(nil)
      create(:app_setting)
      expect { AppSetting.voyage_configured? }.not_to raise_error
      expect(AppSetting.voyage_configured?).to be(false)
    end
  end

  # Phase 29 (settings refactor) — `voyage_indexing_project_notes?` is
  # now a thin alias for `voyage_configured?`. The per-target column
  # column was dropped along with the Voyage.ai pane.
  describe ".voyage_indexing_project_notes?" do
    it "matches voyage_configured? (true when key present)" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return("vk_from_creds")
      expect(AppSetting.voyage_indexing_project_notes?).to be(true)
    end

    it "matches voyage_configured? (false when key absent)" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return(nil)
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

  # Phase 32 follow-up (2026-05-16) — three-layer reindex lock.
  # The two new columns (`reindex_running`, `reindex_started_at`) are
  # install-wide singletons read/written via class methods that promote
  # one canonical `key = "__singleton__"` row to be the lock anchor.
  describe "reindex lock accessors" do
    describe ".singleton_row" do
      it "creates the canonical row on first access" do
        pending "validated manually first; spec fills in after the operator " \
                "confirms the singleton-row creation lands cleanly"
        raise "pending placeholder"
      end

      it "reuses the same row on subsequent accesses (idempotent)" do
        pending "validated manually first"
        raise "pending placeholder"
      end
    end

    describe ".reindex_running?" do
      it "defaults to false on a fresh install" do
        pending "validated manually first"
        raise "pending placeholder"
      end

      it "returns true after start_reindex! flips the flag" do
        pending "validated manually first"
        raise "pending placeholder"
      end
    end

    describe ".reindex_started_at" do
      it "is nil when idle" do
        pending "validated manually first"
        raise "pending placeholder"
      end

      it "carries the started-at timestamp while a reindex is running" do
        pending "validated manually first"
        raise "pending placeholder"
      end
    end

    describe ".start_reindex!" do
      it "sets reindex_running to true and stamps reindex_started_at " \
         "to Time.current in one atomic update" do
        pending "validated manually first"
        raise "pending placeholder"
      end
    end

    describe ".clear_reindex_lock!" do
      it "resets reindex_running to false and nils reindex_started_at" do
        pending "validated manually first"
        raise "pending placeholder"
      end

      it "is idempotent — safe to invoke repeatedly when already clear" do
        pending "validated manually first"
        raise "pending placeholder"
      end
    end
  end
end
