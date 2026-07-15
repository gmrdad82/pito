# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Youtube::LifetimeVideoReport, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:channel) { create(:channel) }
  let(:client)  { instance_double(Channel::Youtube::AnalyticsClient) }
  let(:rows) do
    [
      { video_id: "vid1", views: 100, estimated_minutes_watched: 500, subscribers_gained: 3, subscribers_lost: 1, likes: 10 },
      { video_id: "vid2", views: 50,  estimated_minutes_watched: 200, subscribers_gained: 1, subscribers_lost: 0, likes: 5 }
    ]
  end
  let(:cache_key) { "pito:yt:lifetime_top_videos:v1:channel:#{channel.id}" }

  # All frozen clocks hang off a RELATIVE anchor — absolute dates gave this
  # file a 24h fuse (cache entries seeded under a frozen 2026-07-14 clock
  # expired when the REAL clock passed 2026-07-15 08:00 and un-frozen reads
  # returned nil). Never freeze to a literal date here.
  let(:base) { (Time.current - 2.days).change(hour: 8, min: 0, sec: 0, usec: 0) }


  before do
    # Real cache so fetch/read/write semantics are exercised (test env defaults to :null_store).
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(client)
    allow(client).to receive(:top_videos).and_return(rows)
  end

  describe "cold cache" do
    it "fetches top_videos over the full lifetime range and returns the rows" do
      result = described_class.rows_for(channel: channel, max_age: 12.hours)

      expect(client).to have_received(:top_videos).once.with(
        channel_id: channel.youtube_channel_id,
        start_date: Date.new(2005, 1, 1),
        end_date:   Date.current
      )
      expect(result).to eq(rows)
    end

    it "writes the rows and a fetched_at timestamp to the shared per-channel cache key" do
      travel_to(base) do
        described_class.rows_for(channel: channel, max_age: 12.hours)

        entry = Rails.cache.read(cache_key)
        expect(entry[:rows]).to eq(rows)
        expect(entry[:fetched_at]).to eq(base)
      end
    end
  end

  describe "cache freshness" do
    it "returns the cached rows without refetching while still within max_age" do
      travel_to(base) do
        described_class.rows_for(channel: channel, max_age: 12.hours)
      end

      result = nil
      travel_to(base + 4.hours) do # 4h later — within the 12h max_age
        result = described_class.rows_for(channel: channel, max_age: 12.hours)
      end

      expect(result).to eq(rows)
      expect(client).to have_received(:top_videos).once
    end

    it "refetches and rewrites the cache once the entry is older than max_age" do
      new_rows = [ { video_id: "vid3", views: 999, estimated_minutes_watched: 10, subscribers_gained: 0, subscribers_lost: 0, likes: 0 } ]

      travel_to(base) do
        described_class.rows_for(channel: channel, max_age: 12.hours)
      end

      allow(client).to receive(:top_videos).and_return(new_rows)

      result = nil
      travel_to(base + 13.hours) do # 13h later — stale for a 12h max_age
        result = described_class.rows_for(channel: channel, max_age: 12.hours)

        entry = Rails.cache.read(cache_key)
        expect(entry[:rows]).to eq(new_rows)
        expect(entry[:fetched_at]).to eq(base + 13.hours)
      end

      expect(result).to eq(new_rows)
      expect(client).to have_received(:top_videos).twice
    end
  end

  describe "shared cache across callers with different max_age" do
    it "lets a looser caller read the same entry a stricter caller must refetch" do
      travel_to(base - 2.hours) do
        described_class.rows_for(channel: channel, max_age: 24.hours) # seeds the shared entry
      end

      new_rows = [ { video_id: "vid9", views: 1, estimated_minutes_watched: 1, subscribers_gained: 0, subscribers_lost: 0, likes: 0 } ]

      travel_to(base + 16.hours) do # entry is now 18h old
        # 24h max_age caller: 18h < 24h — reads the shared cache, no refetch.
        result_24h = described_class.rows_for(channel: channel, max_age: 24.hours)
        expect(result_24h).to eq(rows)
        expect(client).to have_received(:top_videos).once

        # 12h max_age caller: 18h > 12h — forces a refetch that rewrites the shared entry.
        allow(client).to receive(:top_videos).and_return(new_rows)
        result_12h = described_class.rows_for(channel: channel, max_age: 12.hours)
        expect(result_12h).to eq(new_rows)
        expect(client).to have_received(:top_videos).twice
      end
    end
  end

  describe "error honesty" do
    it "propagates a Channel::Youtube::Error and leaves the previous cache entry untouched" do
      travel_to(base) do
        described_class.rows_for(channel: channel, max_age: 12.hours) # seeds the cache
      end

      allow(client).to receive(:top_videos).and_raise(Channel::Youtube::Error, "boom")

      travel_to(base + 14.hours) do # stale for a 12h max_age — forces a refetch attempt
        expect {
          described_class.rows_for(channel: channel, max_age: 12.hours)
        }.to raise_error(Channel::Youtube::Error, "boom")
      end

      travel_to(base + 15.hours) do
        entry = Rails.cache.read(cache_key)
        expect(entry[:rows]).to eq(rows)
        expect(entry[:fetched_at]).to eq(base)
      end
    end
  end

  describe "guards" do
    context "when the channel has no youtube_connection" do
      let(:channel) { create(:channel, :orphan) }

      it "returns [] without calling top_videos or touching the cache" do
        result = described_class.rows_for(channel: channel, max_age: 12.hours)

        expect(result).to eq([])
        expect(client).not_to have_received(:top_videos)
        expect(Rails.cache.read(cache_key)).to be_nil
      end
    end

    context "when the channel has no youtube_channel_id" do
      # youtube_channel_id is NOT NULL at the DB level (db/schema.rb) — a
      # factory-created Channel can never carry a nil id, so stub the reader
      # directly rather than fight the constraint.
      before { allow(channel).to receive(:youtube_channel_id).and_return(nil) }

      it "returns [] without calling top_videos or touching the cache" do
        result = described_class.rows_for(channel: channel, max_age: 12.hours)

        expect(result).to eq([])
        expect(client).not_to have_received(:top_videos)
        expect(Rails.cache.read(cache_key)).to be_nil
      end
    end

    context "with a malformed legacy cache entry (a bare Array, not the {rows:, fetched_at:} shape)" do
      it "treats it as a miss and refetches" do
        Rails.cache.write(cache_key, rows)

        result = described_class.rows_for(channel: channel, max_age: 12.hours)

        expect(result).to eq(rows)
        expect(client).to have_received(:top_videos).once

        entry = Rails.cache.read(cache_key)
        expect(entry[:rows]).to eq(rows)
      end
    end
  end
end
