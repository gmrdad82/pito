# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationDeliver, type: :job do
  # NotificationDeliveryChannel (Phase-26 AR model) is not yet migrated;
  # stub the constant so the job can resolve channels without an AR table.
  before do
    stub_const("NotificationDeliveryChannel",
               Class.new do
                 def self.for(kind)
                   Pito::Notifications::DeliveryChannel::Base.for(kind)
                 end
               end)
  end

  let(:notification) { create(:notification) }

  describe "#perform — channel selection" do
    it "routes 'in_app' to the InApp channel and returns :ok" do
      channel = instance_double(Pito::Notifications::DeliveryChannel::InApp)
      allow(Pito::Notifications::DeliveryChannel::Base)
        .to receive(:for).with("in_app").and_return(channel)
      allow(channel).to receive(:deliver).with(notification)
        .and_return(Pito::Notifications::DeliveryChannel::Base::Result.new(status: :ok))

      described_class.new.perform(notification.id, "in_app")

      expect(channel).to have_received(:deliver).with(notification)
    end

    it "raises ArgumentError for an unknown channel kind" do
      expect {
        described_class.new.perform(notification.id, "fax")
      }.to raise_error(ArgumentError, /unknown channel/)
    end
  end

  describe "#perform — missing notification" do
    it "is a silent no-op when the row has been deleted" do
      missing_id = notification.id + 99_999
      expect {
        described_class.new.perform(missing_id, "in_app")
      }.not_to raise_error
    end
  end

  describe "#perform — transient failure propagates for Sidekiq retry" do
    it "re-raises TransientFailure so the job retries" do
      # AppSetting.discord_delivery_enabled? is aspirational; define speculatively.
      unless AppSetting.respond_to?(:discord_delivery_enabled?)
        AppSetting.define_singleton_method(:discord_delivery_enabled?) { false }
      end
      allow(AppSetting).to receive(:discord_delivery_enabled?).and_return(false)

      channel = instance_double(Pito::Notifications::DeliveryChannel::Discord)
      allow(Pito::Notifications::DeliveryChannel::Base)
        .to receive(:for).with("discord").and_return(channel)
      allow(channel).to receive(:deliver).and_raise(
        Pito::Notifications::DeliveryChannel::Base::TransientFailure, "rate limited"
      )

      expect {
        described_class.new.perform(notification.id, "discord")
      }.to raise_error(Pito::Notifications::DeliveryChannel::Base::TransientFailure)
    end
  end
end
