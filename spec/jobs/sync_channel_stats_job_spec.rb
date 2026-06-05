# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncChannelStatsJob do
  let!(:active_connection)   { create(:youtube_connection) }
  let!(:reauth_connection)   { create(:youtube_connection, :needs_reauth) }
  let!(:unconnected_channel) { create(:channel) }

  let!(:channel_a) do
    create(:channel,
           youtube_connection: active_connection,
           youtube_channel_id: "UCaaa111",
           subscriber_count: 0,
           view_count: 0,
           watched_hours: 0)
  end

  let!(:channel_b) do
    create(:channel,
           youtube_connection: active_connection,
           youtube_channel_id: "UCbbb222",
           subscriber_count: 0,
           view_count: 0,
           watched_hours: 0)
  end

  let!(:reauth_channel) do
    create(:channel,
           youtube_connection: reauth_connection,
           youtube_channel_id: "UCreauth333",
           subscriber_count: 999,
           view_count: 999)
  end

  let(:fetched_stats_a) do
    { subscriber_count: 10_000, view_count: 500_000, watched_hours: 2_000, last_synced_at: Time.current }
  end
  let(:fetched_stats_b) do
    { subscriber_count: 50_000, view_count: 1_000_000, watched_hours: 8_000, last_synced_at: Time.current }
  end

  before do
    allow(Channel::Youtube::StatsFetcher).to receive(:call) do |ch|
      case ch.youtube_channel_id
      when "UCaaa111" then fetched_stats_a
      when "UCbbb222" then fetched_stats_b
      end
    end
  end

  describe "#perform" do
    subject(:job) { described_class.new }

    it "syncs stats for every channel on an active connection" do
      job.perform

      channel_a.reload
      expect(channel_a.subscriber_count).to eq(10_000)
      expect(channel_a.view_count).to eq(500_000)
      expect(channel_a.watched_hours).to eq(2_000)
      expect(channel_a.last_synced_at).to be_within(5.seconds).of(Time.current)
    end

    it "syncs all channels on the active connection" do
      job.perform

      channel_b.reload
      expect(channel_b.subscriber_count).to eq(50_000)
      expect(channel_b.view_count).to eq(1_000_000)
    end

    it "skips channels whose connection needs_reauth" do
      job.perform

      reauth_channel.reload
      # stats should be unchanged
      expect(reauth_channel.subscriber_count).to eq(999)
      expect(reauth_channel.view_count).to eq(999)
    end

    it "skips channels with no youtube_connection" do
      expect(Channel::Youtube::StatsFetcher).not_to receive(:call).with(unconnected_channel)

      job.perform
    end

    context "when StatsFetcher raises for one channel" do
      before do
        call_count = 0
        allow(Channel::Youtube::StatsFetcher).to receive(:call) do |ch|
          call_count += 1
          if ch.youtube_channel_id == "UCaaa111"
            raise Channel::Youtube::TransientError, "quota exceeded"
          end
          fetched_stats_b
        end
      end

      it "logs the error but continues processing the remaining channels" do
        expect(Rails.logger).to receive(:error).with(/channel=#{channel_a.id}.*quota exceeded/)

        job.perform

        channel_b.reload
        expect(channel_b.subscriber_count).to eq(50_000)
      end

      it "does not update the failing channel" do
        allow(Rails.logger).to receive(:error)

        job.perform

        channel_a.reload
        expect(channel_a.subscriber_count).to eq(0)  # unchanged
      end
    end
  end
end
