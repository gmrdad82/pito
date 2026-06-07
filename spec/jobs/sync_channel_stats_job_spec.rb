# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncChannelStatsJob do
  let!(:active_connection)   { create(:youtube_connection) }
  let!(:reauth_connection)   { create(:youtube_connection, :needs_reauth) }
  let!(:unconnected_channel) { create(:channel) }

  let!(:channel_a) do
    create(:channel,
           youtube_connection: active_connection,
           youtube_channel_id: "UCaaa111")
  end

  let!(:channel_b) do
    create(:channel,
           youtube_connection: active_connection,
           youtube_channel_id: "UCbbb222")
  end

  let!(:reauth_channel) do
    create(:channel,
           youtube_connection: reauth_connection,
           youtube_channel_id: "UCreauth333").tap do |ch|
      Pito::Stats.set(ch, :subscribers, 999)
      Pito::Stats.set(ch, :views, 999)
    end
  end

  let(:fetched_stats_a) do
    { subscriber_count: 10_000, view_count: 500_000, last_synced_at: Time.current }
  end
  let(:fetched_stats_b) do
    { subscriber_count: 50_000, view_count: 1_000_000, last_synced_at: Time.current }
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
      expect(Pito::Stats.get(channel_a, :subscribers)).to eq(10_000)
      expect(Pito::Stats.get(channel_a, :views)).to eq(500_000)
      expect(channel_a.last_synced_at).to be_within(5.seconds).of(Time.current)
    end

    it "syncs all channels on the active connection" do
      job.perform

      expect(Pito::Stats.get(channel_b, :subscribers)).to eq(50_000)
      expect(Pito::Stats.get(channel_b, :views)).to eq(1_000_000)
    end

    it "skips channels whose connection needs_reauth" do
      job.perform

      # stats should be unchanged
      expect(Pito::Stats.get(reauth_channel, :subscribers)).to eq(999)
      expect(Pito::Stats.get(reauth_channel, :views)).to eq(999)
    end

    it "skips channels with no youtube_connection" do
      expect(Channel::Youtube::StatsFetcher).not_to receive(:call).with(unconnected_channel)

      job.perform
    end

    context "when StatsFetcher raises for one channel" do
      before do
        allow(Channel::Youtube::StatsFetcher).to receive(:call) do |ch|
          if ch.youtube_channel_id == "UCaaa111"
            raise Channel::Youtube::TransientError, "quota exceeded"
          end
          fetched_stats_b
        end
      end

      it "logs the error but continues processing the remaining channels" do
        expect(Rails.logger).to receive(:error).with(/channel=#{channel_a.id}.*quota exceeded/)

        job.perform

        expect(Pito::Stats.get(channel_b, :subscribers)).to eq(50_000)
      end

      it "does not update the failing channel" do
        allow(Rails.logger).to receive(:error)

        job.perform

        expect(Pito::Stats.get(channel_a, :subscribers)).to be_nil  # unchanged
      end
    end
  end
end
