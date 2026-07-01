# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppSetting, type: :model do
  describe ".sound_enabled?" do
    it "returns true by default (no row stored)" do
      AppSetting.where(key: AppSetting::SOUND_ENABLED_KEY).delete_all
      expect(AppSetting.sound_enabled?).to be true
    end

    it "returns false when the stored value is 'false'" do
      AppSetting.sound_enabled = false
      expect(AppSetting.sound_enabled?).to be false
    end

    it "returns true when the stored value is 'true'" do
      AppSetting.sound_enabled = false
      AppSetting.sound_enabled = true
      expect(AppSetting.sound_enabled?).to be true
    end
  end

  describe ".sound_enabled=" do
    it "persists the value as a string" do
      AppSetting.sound_enabled = false
      expect(AppSetting.get(AppSetting::SOUND_ENABLED_KEY)).to eq("false")
    end

    it "coerces truthy to 'true'" do
      AppSetting.sound_enabled = true
      expect(AppSetting.get(AppSetting::SOUND_ENABLED_KEY)).to eq("true")
    end
  end

  # (fx_enabled / fx_effect were removed in item 18 — content motion + the
  # /config motion|fx settings are gone.)

  describe ".theme" do
    it "returns the default slug when no row is stored" do
      AppSetting.where(key: AppSetting::THEME_KEY).delete_all
      expect(AppSetting.theme).to eq("tokyo-night")
    end

    it "returns the stored slug after assignment" do
      AppSetting.theme = "dracula"
      expect(AppSetting.theme).to eq("dracula")
    end

    it "round-trips back to the default after re-assignment" do
      AppSetting.theme = "dracula"
      AppSetting.theme = "tokyo-night"
      expect(AppSetting.theme).to eq("tokyo-night")
    end
  end

  describe ".theme=" do
    it "persists the slug as a string" do
      AppSetting.theme = "dracula"
      expect(AppSetting.get(AppSetting::THEME_KEY)).to eq("dracula")
    end

    it "overwrites a previous value" do
      AppSetting.theme = "dracula"
      AppSetting.theme = "tokyo-night"
      expect(AppSetting.get(AppSetting::THEME_KEY)).to eq("tokyo-night")
    end
  end

  describe ".timezone" do
    it "returns UTC by default (no row stored)" do
      AppSetting.where(key: AppSetting::TIMEZONE_KEY).delete_all
      expect(AppSetting.timezone).to eq("UTC")
    end

    it "returns the stored IANA identifier after assignment" do
      AppSetting.timezone = "Madrid"
      expect(AppSetting.timezone).to eq("Europe/Madrid")
    end
  end

  describe ".nickname" do
    before { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }
    after  { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }

    it "returns 'gmrdad82' by default when no row is stored" do
      expect(AppSetting.nickname).to eq("gmrdad82")
    end

    it "returns the stored value after assignment" do
      AppSetting.nickname = "Foo"
      expect(AppSetting.nickname).to eq("Foo")
    end
  end

  describe ".nickname=" do
    before { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }
    after  { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }

    it "persists the value as a string" do
      AppSetting.nickname = "streamer"
      expect(AppSetting.get(AppSetting::NICKNAME_KEY)).to eq("streamer")
    end

    it "overwrites a previous value" do
      AppSetting.nickname = "first"
      AppSetting.nickname = "second"
      expect(AppSetting.nickname).to eq("second")
    end
  end

  describe ".timezone=" do
    it "normalizes a major-city name to its IANA identifier" do
      AppSetting.timezone = "Tokyo"
      expect(AppSetting.get(AppSetting::TIMEZONE_KEY)).to eq("Asia/Tokyo")
    end

    it "accepts a raw IANA identifier" do
      AppSetting.timezone = "Europe/Madrid"
      expect(AppSetting.get(AppSetting::TIMEZONE_KEY)).to eq("Europe/Madrid")
    end

    it "raises ArgumentError for an unknown zone and persists nothing" do
      AppSetting.where(key: AppSetting::TIMEZONE_KEY).delete_all
      expect { AppSetting.timezone = "Nowhereville" }.to raise_error(ArgumentError)
      expect(AppSetting.get(AppSetting::TIMEZONE_KEY)).to be_nil
    end
  end
end
