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

  describe ".expand_all?" do
    it "returns false by default (no row stored)" do
      AppSetting.where(key: AppSetting::EXPAND_ALL_KEY).delete_all
      expect(AppSetting.expand_all?).to be false
    end

    it "returns true when the stored value is 'true'" do
      AppSetting.expand_all = true
      expect(AppSetting.expand_all?).to be true
    end

    it "returns false when the stored value is 'false'" do
      AppSetting.expand_all = true
      AppSetting.expand_all = false
      expect(AppSetting.expand_all?).to be false
    end
  end

  describe ".expand_all=" do
    it "persists the value as a string" do
      AppSetting.expand_all = true
      expect(AppSetting.get(AppSetting::EXPAND_ALL_KEY)).to eq("true")
    end

    it "coerces falsy to 'false'" do
      AppSetting.expand_all = false
      expect(AppSetting.get(AppSetting::EXPAND_ALL_KEY)).to eq("false")
    end
  end
end
