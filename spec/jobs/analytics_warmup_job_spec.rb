# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyticsWarmupJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new }

  before do
    allow(Pito::Analytics::Warmup).to receive(:call)
  end

  # ─── connected channels ─────────────────────────────────────────────────────

  describe "connected channels" do
    let!(:connection) { create(:youtube_connection, :with_channels) }

    it "calls Warmup once per connected channel with the channel kwarg" do
      job.perform

      connection.channels.each do |channel|
        expect(Pito::Analytics::Warmup).to have_received(:call).with(channel:).once
      end
    end

    it "calls Warmup exactly as many times as there are connected channels" do
      job.perform

      expect(Pito::Analytics::Warmup).to have_received(:call).exactly(connection.channels.count).times
    end
  end

  # ─── skips needs_reauth channels ────────────────────────────────────────────

  describe "skipping needs_reauth channels" do
    let!(:reauth_connection) { create(:youtube_connection, :needs_reauth, :with_channels) }

    it "does not call Warmup for a channel whose connection needs_reauth" do
      job.perform

      reauth_connection.channels.each do |channel|
        expect(Pito::Analytics::Warmup).not_to have_received(:call).with(channel:)
      end
    end
  end

  # ─── per-channel error isolation ────────────────────────────────────────────

  describe "per-channel error isolation" do
    let!(:connection) { create(:youtube_connection, :with_channels) }

    before do
      first_channel = connection.channels.order(:id).first
      allow(Pito::Analytics::Warmup).to receive(:call).with(channel: first_channel)
        .and_raise(StandardError, "warmup boom")
    end

    it "does not raise even if the first channel's warmup errors" do
      expect { job.perform }.not_to raise_error
    end

    it "still warms the second channel" do
      second_channel = connection.channels.order(:id).last

      job.perform

      expect(Pito::Analytics::Warmup).to have_received(:call).with(channel: second_channel)
    end

    it "logs the error for the failing channel" do
      first_channel = connection.channels.order(:id).first

      expect(Rails.logger).to receive(:error)
        .with(/AnalyticsWarmupJob.*channel=#{first_channel.id}.*warmup boom/)

      job.perform
    end

    # Reported to AppSignal AND isolated — never re-raised, siblings warm on.
    it "reports the error to AppSignal without breaking isolation" do
      allow(Appsignal).to receive(:report_error)
      second_channel = connection.channels.order(:id).last

      expect { job.perform }.not_to raise_error

      expect(Appsignal).to have_received(:report_error)
        .with(an_instance_of(StandardError).and(having_attributes(message: "warmup boom")))
      expect(Pito::Analytics::Warmup).to have_received(:call).with(channel: second_channel)
    end
  end

  # ─── no channels ────────────────────────────────────────────────────────────

  describe "no connected channels" do
    it "does not call Warmup" do
      job.perform

      expect(Pito::Analytics::Warmup).not_to have_received(:call)
    end

    it "does not raise" do
      expect { job.perform }.not_to raise_error
    end
  end
end
