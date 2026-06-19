# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
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
