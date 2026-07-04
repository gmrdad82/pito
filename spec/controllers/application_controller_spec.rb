# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  describe "#hotwire_native_app?" do
    it "is true when the User-Agent carries the Hotwire Native marker" do
      request.user_agent = "Mozilla/5.0 (Linux; Android 14) Hotwire Native Android"
      expect(controller.send(:hotwire_native_app?)).to be true
    end

    it "is false for an ordinary browser User-Agent" do
      request.user_agent = "Mozilla/5.0 (Linux; Android 14) Chrome/126.0"
      expect(controller.send(:hotwire_native_app?)).to be false
    end

    it "is false when the User-Agent is absent" do
      request.user_agent = nil
      expect(controller.send(:hotwire_native_app?)).to be false
    end

    it "is exposed to views as a helper" do
      expect(described_class.helpers).to respond_to(:hotwire_native_app?)
    end
  end

  describe "#set_user_time_zone" do
    around do |example|
      original = Time.zone
      example.run
      Time.zone = original
    end

    it "sets Time.zone from AppSetting.timezone" do
      AppSetting.timezone = "Madrid"
      controller.send(:set_user_time_zone)
      expect(Time.zone.tzinfo.identifier).to eq("Europe/Madrid")
    end

    it "falls back to UTC when reading the setting raises" do
      allow(AppSetting).to receive(:timezone).and_raise(StandardError)
      controller.send(:set_user_time_zone)
      expect(Time.zone.tzinfo.identifier).to eq("Etc/UTC")
    end
  end
end
