require "rails_helper"
require Rails.root.join(
  "db/migrate/20260511021116_add_keyboard_navigation_enabled_to_app_settings.rb"
)

# 2026-05-11 — keyboard-navigation master toggle migration.
#
# Drives the `change` body up and down on the live test DB to prove
# reversibility. The example block leaves the test DB in the
# post-migration state regardless of mid-example failure so neighbour
# specs keep working.
RSpec.describe AddKeyboardNavigationEnabledToAppSettings, type: :model do
  def column_for(name)
    ActiveRecord::Base.connection.columns(:app_settings).find { |c| c.name == name.to_s }
  end

  describe "post-migration state" do
    it "adds the keyboard_navigation_enabled column" do
      expect(column_for(:keyboard_navigation_enabled)).not_to be_nil
    end

    it "stores the column as a boolean, NOT NULL, defaulting to true" do
      col = column_for(:keyboard_navigation_enabled)
      expect(col.sql_type).to eq("boolean")
      expect(col.null).to be(false)
      # ActiveRecord's PostgreSQL adapter returns the cast Boolean for
      # `default` on boolean columns (not a string literal).
      expect(col.default).to be(true)
    end
  end

  describe "rollback + re-apply" do
    around do |example|
      example.run
    ensure
      unless column_for(:keyboard_navigation_enabled)
        described_class.new.migrate(:up)
      end
    end

    it "removes the column on `down` and restores it on `up`" do
      described_class.new.migrate(:down)
      expect(column_for(:keyboard_navigation_enabled)).to be_nil

      described_class.new.migrate(:up)
      expect(column_for(:keyboard_navigation_enabled)).not_to be_nil
    end
  end
end
