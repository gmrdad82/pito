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

  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The per-brand `everything` /
  # `daily_digest` columns were dropped. Delivery gates are now an AND
  # of:
  #
  #   1. Shared toggle ON (`notifications_send_all` OR
  #      `notifications_send_daily_digest`) — read off the singleton row.
  #   2. A `NotificationDeliveryChannel` row exists for the kind with a
  #      present `webhook_url`.
  shared_examples "a delivery-channel gate predicate" do |kind, predicate, valid_url|
    before { AppSetting.delete_all }

    it "returns false when no #{kind} channel row exists (toggle off too)" do
      expect(AppSetting.public_send(predicate)).to be(false)
    end

    it "returns false when channel exists but BOTH shared toggles are off" do
      NotificationDeliveryChannel.create!(kind: kind, webhook_url: valid_url)
      expect(AppSetting.public_send(predicate)).to be(false)
    end

    it "returns false when a shared toggle is on but no channel row exists" do
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      expect(AppSetting.public_send(predicate)).to be(false)
    end

    it "returns false when shared toggle is on but webhook_url is blank" do
      channel = NotificationDeliveryChannel.new(kind: kind, webhook_url: "")
      channel.save!(validate: false)
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      expect(AppSetting.public_send(predicate)).to be(false)
    end

    it "returns true with a webhook_url and `notifications_send_all` set" do
      NotificationDeliveryChannel.create!(kind: kind, webhook_url: valid_url)
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      expect(AppSetting.public_send(predicate)).to be(true)
    end

    it "returns true with a webhook_url and `notifications_send_daily_digest` set" do
      NotificationDeliveryChannel.create!(kind: kind, webhook_url: valid_url)
      AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
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

  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The two shared notification
  # toggles live on the canonical `AppSetting.singleton_row`. The
  # class-level accessors below front the singleton-row columns so the
  # web form, the worker, the helper, and the JSON wire all read from
  # the same surface.
  describe "shared notification toggles" do
    before { AppSetting.delete_all }

    describe ".notifications_send_all?" do
      it "defaults to false on a fresh install" do
        expect(AppSetting.notifications_send_all?).to be(false)
      end

      it "is true after set_notification_toggle!(:notifications_send_all, true)" do
        AppSetting.set_notification_toggle!(:notifications_send_all, true)
        expect(AppSetting.notifications_send_all?).to be(true)
      end
    end

    describe ".notifications_send_daily_digest?" do
      it "defaults to false on a fresh install" do
        expect(AppSetting.notifications_send_daily_digest?).to be(false)
      end

      it "is true after set_notification_toggle!(:notifications_send_daily_digest, true)" do
        AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
        expect(AppSetting.notifications_send_daily_digest?).to be(true)
      end
    end

    describe ".notifications_any_toggle_on?" do
      it "is false when both toggles are off" do
        expect(AppSetting.notifications_any_toggle_on?).to be(false)
      end

      it "is true when only `all` is on" do
        AppSetting.set_notification_toggle!(:notifications_send_all, true)
        expect(AppSetting.notifications_any_toggle_on?).to be(true)
      end

      it "is true when only `daily_digest` is on" do
        AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
        expect(AppSetting.notifications_any_toggle_on?).to be(true)
      end

      it "is true when both toggles are on" do
        AppSetting.set_notification_toggle!(:notifications_send_all, true)
        AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
        expect(AppSetting.notifications_any_toggle_on?).to be(true)
      end
    end

    describe ".set_notification_toggle!" do
      it "raises ArgumentError on an unknown column" do
        expect {
          AppSetting.set_notification_toggle!(:notifications_send_carrier_pigeon, true)
        }.to raise_error(ArgumentError, /unknown notification toggle/)
      end

      it "coerces truthy to true and falsy to false" do
        AppSetting.set_notification_toggle!(:notifications_send_all, "yes")
        expect(AppSetting.notifications_send_all?).to be(true)
        AppSetting.set_notification_toggle!(:notifications_send_all, nil)
        expect(AppSetting.notifications_send_all?).to be(false)
      end

      it "is idempotent" do
        AppSetting.set_notification_toggle!(:notifications_send_all, true)
        expect {
          AppSetting.set_notification_toggle!(:notifications_send_all, true)
        }.not_to raise_error
        expect(AppSetting.notifications_send_all?).to be(true)
      end
    end
  end

  # Phase 32 follow-up (2026-05-16) — three-layer reindex lock.
  # The two new columns (`reindex_running`, `reindex_started_at`) are
  # install-wide singletons read/written via class methods that promote
  # one canonical `key = "__singleton__"` row to be the lock anchor.
  describe "reindex lock accessors" do
    before { AppSetting.delete_all }

    describe ".singleton_row" do
      it "creates the canonical row on first access" do
        expect { AppSetting.singleton_row }.to change(AppSetting, :count).by(1)
        expect(AppSetting.singleton_row.key).to eq("__singleton__")
      end

      it "reuses the same row on subsequent accesses (idempotent)" do
        first = AppSetting.singleton_row
        second = AppSetting.singleton_row
        expect(second.id).to eq(first.id)
        expect(AppSetting.where(key: "__singleton__").count).to eq(1)
      end
    end

    describe ".reindex_running?" do
      it "defaults to false on a fresh install" do
        expect(AppSetting.reindex_running?).to be(false)
      end

      it "returns true after start_reindex! flips the flag" do
        AppSetting.start_reindex!
        expect(AppSetting.reindex_running?).to be(true)
      end
    end

    describe ".reindex_started_at" do
      it "is nil when idle" do
        expect(AppSetting.reindex_started_at).to be_nil
      end

      it "carries the started-at timestamp while a reindex is running" do
        AppSetting.start_reindex!
        expect(AppSetting.reindex_started_at).not_to be_nil
        expect(AppSetting.reindex_started_at).to be_within(5.seconds).of(Time.current)
      end
    end

    describe ".start_reindex!" do
      it "sets reindex_running to true and stamps reindex_started_at " \
         "to Time.current in one atomic update" do
        AppSetting.start_reindex!
        row = AppSetting.singleton_row
        aggregate_failures do
          expect(row.reindex_running).to be(true)
          expect(row.reindex_started_at).not_to be_nil
          expect(row.reindex_started_at).to be_within(5.seconds).of(Time.current)
        end
      end
    end

    describe ".clear_reindex_lock!" do
      it "resets reindex_running to false and nils reindex_started_at" do
        AppSetting.start_reindex!
        AppSetting.clear_reindex_lock!
        row = AppSetting.singleton_row
        aggregate_failures do
          expect(row.reindex_running).to be(false)
          expect(row.reindex_started_at).to be_nil
        end
      end

      it "is idempotent — safe to invoke repeatedly when already clear" do
        expect { AppSetting.clear_reindex_lock! }.not_to raise_error
        expect { AppSetting.clear_reindex_lock! }.not_to raise_error
        row = AppSetting.singleton_row
        expect(row.reindex_running).to be(false)
        expect(row.reindex_started_at).to be_nil
      end
    end
  end
end
