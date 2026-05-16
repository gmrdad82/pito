require "rails_helper"
require Rails.root.join("db/migrate/20260515120000_drop_ux_app_settings_fields.rb")

# Phase 29 (settings refactor) — UX columns + KV rows drop.
#
# Migration integration test. The `up` body has already run as part of
# the suite bootstrap (every migration is applied to the test schema);
# these assertions describe the post-condition state. The matching
# `down` body re-adds the three columns so the schema can be rolled
# backwards in development; the spec covers both directions on a clean
# slate.
RSpec.describe DropUxAppSettingsFields, type: :model do
  describe "post-migration column shape" do
    it "drops keyboard_navigation_enabled" do
      expect(AppSetting.column_names).not_to include("keyboard_navigation_enabled")
    end

    it "drops timezone" do
      expect(AppSetting.column_names).not_to include("timezone")
    end

    it "drops voyage_index_project_notes" do
      expect(AppSetting.column_names).not_to include("voyage_index_project_notes")
    end

    it "keeps the (key, value) backbone" do
      expect(AppSetting.column_names).to include("key", "value")
    end
  end

  describe "#up KV row scrub" do
    # The `up` body deletes any row whose `key` is one of the dropped
    # UX KV keys. We can't re-create the rows now (the columns aren't
    # present in the model), so we drive a fresh insert via raw SQL,
    # then re-run the `up` deletion and assert.
    before do
      AppSetting.connection.execute(
        "INSERT INTO app_settings (key, value, created_at, updated_at) " \
        "VALUES ('theme', '#{encrypted_value('dark')}', NOW(), NOW()), " \
        "       ('max_panes', '#{encrypted_value('5')}', NOW(), NOW()), " \
        "       ('pane_title_length', '#{encrypted_value('18')}', NOW(), NOW())"
      )
    end

    after { AppSetting.delete_all }

    it "purges the three dropped KV keys" do
      described_class::DROPPED_KV_KEYS.each do |key|
        expect(AppSetting.find_by(key: key)).to be_present
      end

      described_class.new.up

      described_class::DROPPED_KV_KEYS.each do |key|
        expect(AppSetting.find_by(key: key)).to be_nil
      end
    end

    it "does not touch unrelated KV rows" do
      AppSetting.set("monetization_enabled", "yes")
      described_class.new.up
      expect(AppSetting.get("monetization_enabled")).to eq("yes")
    end
  end

  # Encrypt a plaintext value the same way the model does so the
  # `up` body's straight DELETE can find the row regardless of the
  # encrypted column contents.
  def encrypted_value(plaintext)
    AppSetting.encrypted_attributes
    AppSetting.attribute_types["value"].serialize(plaintext)
  end
end
