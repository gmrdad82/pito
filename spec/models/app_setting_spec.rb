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

  # Phase 4 §3.5 (2026-05-04 post-review refinement) — Voyage call gating
  # lives on the first AppSetting row (the de-facto singleton seeded in
  # db/seeds.rb). Replaces the previous Rails.application.config flag.
  describe "voyage_embeddings_enabled column" do
    it "defaults to false on a freshly created row" do
      setting = create(:app_setting)
      expect(setting.voyage_embeddings_enabled).to be(false)
    end

    it "is updatable without raising" do
      setting = create(:app_setting)
      expect { setting.update!(voyage_embeddings_enabled: true) }.not_to raise_error
      expect(setting.reload.voyage_embeddings_enabled).to be(true)
    end
  end

  describe ".voyage_embeddings_enabled?" do
    it "returns false when no AppSetting row exists" do
      AppSetting.delete_all
      expect(AppSetting.voyage_embeddings_enabled?).to be(false)
    end

    it "returns the singleton's column value when the row exists" do
      AppSetting.delete_all
      create(:app_setting, key: "max_panes", value: "5", voyage_embeddings_enabled: true)
      expect(AppSetting.voyage_embeddings_enabled?).to be(true)
    end

    it "returns false when the singleton's column is false" do
      AppSetting.delete_all
      create(:app_setting, key: "max_panes", value: "5", voyage_embeddings_enabled: false)
      expect(AppSetting.voyage_embeddings_enabled?).to be(false)
    end

    it "is idempotent across repeated flips" do
      AppSetting.delete_all
      setting = create(:app_setting, key: "max_panes", value: "5")
      setting.update!(voyage_embeddings_enabled: true)
      expect(AppSetting.voyage_embeddings_enabled?).to be(true)
      setting.update!(voyage_embeddings_enabled: false)
      expect(AppSetting.voyage_embeddings_enabled?).to be(false)
    end
  end
end
