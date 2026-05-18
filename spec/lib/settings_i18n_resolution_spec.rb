require "rails_helper"

# Lane C surface coverage — settings i18n key resolution smoke.
#
# 2026-05-18 — guard against future key drift. Scans every settings
# controller file under `app/controllers/settings_controller.rb` and
# `app/controllers/settings/**/*.rb` for `t("settings.…")` calls and
# verifies each key resolves via `I18n.t(key, default: nil)`.
#
# Dynamic interpolation segments (e.g. `t("settings.foo.#{var}")`)
# cannot be statically resolved; for those, the spec verifies the
# parent namespace exists in the locale tree instead of the literal
# string with `#{…}` substitution.
RSpec.describe "settings i18n key resolution" do
  SETTINGS_CONTROLLER_FILES = (
    Dir[Rails.root.join("app/controllers/settings/**/*.rb").to_s] +
    [ Rails.root.join("app/controllers/settings_controller.rb").to_s ]
  ).select { |path| File.file?(path) }

  # Pull every `t("settings.…")` literal out of the controller sources.
  EXTRACTED_KEYS = SETTINGS_CONTROLLER_FILES.flat_map do |path|
    File.read(path).scan(/\bt\(\s*"(settings\.[^"]+)"/).flatten
  end.uniq.sort

  describe "extraction sanity" do
    it "finds at least one t(\"settings.*\") call in the controllers" do
      expect(EXTRACTED_KEYS).not_to be_empty
    end

    it "includes the two reindex flash keys exercised by /settings/reindex" do
      expect(EXTRACTED_KEYS).to include("settings.flash.reindex_started")
      expect(EXTRACTED_KEYS).to include("settings.flash.reindex_in_progress")
    end

    it "includes the legacy `settings.flash.saved` notice from SettingsController#update" do
      expect(EXTRACTED_KEYS).to include("settings.flash.saved")
    end
  end

  describe "every static key resolves to a non-nil string" do
    EXTRACTED_KEYS.reject { |k| k.include?('#{') }.each do |key|
      it "resolves `#{key}`" do
        value = I18n.t(key, default: nil)
        expect(value).not_to be_nil, "expected i18n key `#{key}` to resolve, but I18n.t returned nil"
        expect(value).to be_a(String).or be_a(Hash)
      end
    end
  end

  describe "dynamic-segment keys have a populated parent namespace" do
    # For `t("settings.foo.#{var}")` we cannot know the runtime value of
    # `var`, but we can assert the namespace under which the lookup
    # happens (`settings.foo`) exists and is a populated hash. This
    # catches "you renamed the namespace and the dynamic lookup now
    # always falls back to default" drift.
    DYNAMIC_KEYS = EXTRACTED_KEYS.select { |k| k.include?('#{') }

    DYNAMIC_KEYS.each do |key|
      namespace = key.split('.').take_while { |seg| !seg.include?('#{') }.join('.')

      it "`#{namespace}` namespace exists (from `#{key}`)" do
        next if namespace.empty?
        value = I18n.t(namespace, default: nil)
        expect(value).to be_a(Hash), "expected i18n namespace `#{namespace}` to exist as a Hash"
        expect(value).not_to be_empty
      end
    end
  end

  describe "critical keys round-trip the expected English copy" do
    # Lock the most operator-visible copy strings so a future
    # locale-file edit cannot silently change them out from under the
    # /settings UI.
    {
      "settings.flash.saved" => "settings saved.",
      "settings.flash.reindex_started" => "reindex started.",
      "settings.flash.reindex_in_progress" => "reindex already in progress.",
      "settings.time_zone.flash.saved" => "time zone saved.",
      "settings.user.flash.updated" => "account updated.",
      "settings.discord.flash.updated" => "Discord webhook updated.",
      "settings.slack.flash.updated" => "Slack webhook updated."
    }.each do |key, expected|
      it "`#{key}` → `#{expected}`" do
        expect(I18n.t(key, default: nil)).to eq(expected)
      end
    end
  end
end
