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

  describe ".fx_enabled?" do
    it "returns true by default (no row stored)" do
      AppSetting.where(key: AppSetting::FX_ENABLED_KEY).delete_all
      expect(AppSetting.fx_enabled?).to be true
    end

    it "returns false when the stored value is 'false'" do
      AppSetting.fx_enabled = false
      expect(AppSetting.fx_enabled?).to be false
    end

    it "returns true when the stored value is 'true'" do
      AppSetting.fx_enabled = false
      AppSetting.fx_enabled = true
      expect(AppSetting.fx_enabled?).to be true
    end
  end

  describe ".fx_enabled=" do
    it "persists the value as a string" do
      AppSetting.fx_enabled = false
      expect(AppSetting.get(AppSetting::FX_ENABLED_KEY)).to eq("false")
    end

    it "coerces truthy to 'true'" do
      AppSetting.fx_enabled = true
      expect(AppSetting.get(AppSetting::FX_ENABLED_KEY)).to eq("true")
    end
  end

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
end
