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
