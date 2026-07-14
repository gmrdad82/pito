# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Youtube::VideoStatsReadThrough do
  include ActiveSupport::Testing::TimeHelpers

  # ─── helpers ────────────────────────────────────────────────────────────────

  # Build a minimal videos.list response item for a given youtube_video_id.
  def make_item(id, views: "100", likes: "10", comments: "5")
    {
      id: id,
      statistics: {
        view_count:    views,
        like_count:    likes,
        comment_count: comments
      }
    }
  end

  let(:max_age) { 3.hours }
  let(:connection) { create(:youtube_connection) }
  let!(:channel) { create(:channel, youtube_connection: connection) }

  # ─── FRESH ──────────────────────────────────────────────────────────────────

  describe "fresh rows" do
    let!(:video1) { create(:video, channel: channel, youtube_video_id: "vid1") }
    let!(:video2) { create(:video, channel: channel, youtube_video_id: "vid2") }

    before do
      Pito::Stats.set(video1, :views,    1_000)
      Pito::Stats.set(video1, :likes,    100)
      Pito::Stats.set(video1, :comments, 10)

      Pito::Stats.set(video2, :views,    2_000)
      Pito::Stats.set(video2, :likes,    200)
      Pito::Stats.set(video2, :comments, 20)
    end

    it "never calls videos_list" do
      expect(Channel::Youtube::Client).not_to receive(:new)
      described_class.call(channel: channel, max_age: max_age)
    end

    it "serves both videos from the DB with correct values" do
      result = described_class.call(channel: channel, max_age: max_age)

      expect(result).to eq(
        "vid1" => { views: 1_000, likes: 100, comments: 10 },
        "vid2" => { views: 2_000, likes: 200, comments: 20 }
      )
    end
  end

  # ─── STALE ──────────────────────────────────────────────────────────────────

  describe "stale rows" do
    let!(:video1) { create(:video, channel: channel, youtube_video_id: "vid1") }
    let!(:video2) { create(:video, channel: channel, youtube_video_id: "vid2") }
    let!(:video3) { create(:video, channel: channel, youtube_video_id: "vid3") }

    before do
      travel_to(4.hours.ago) do
        Pito::Stats.set(video1, :views,    1)
        Pito::Stats.set(video1, :likes,    1)
        Pito::Stats.set(video1, :comments, 1)

        Pito::Stats.set(video2, :views,    2)
        Pito::Stats.set(video2, :likes,    2)
        Pito::Stats.set(video2, :comments, 2)

        Pito::Stats.set(video3, :views,    3)
        Pito::Stats.set(video3, :likes,    3)
        Pito::Stats.set(video3, :comments, 3)
      end
    end

    it "calls videos_list exactly once with all stale ids in one slice" do
      received_calls = []
      client = instance_double(Channel::Youtube::Client)
      allow(client).to receive(:videos_list) do |ids:, parts:|
        received_calls << ids
        {
          items: [
            make_item("vid1", views: "111", likes: "11", comments: "1"),
            make_item("vid2", views: "222", likes: "22", comments: "2"),
            make_item("vid3", views: "333", likes: "33", comments: "3")
          ]
        }
      end
      allow(Channel::Youtube::Client).to receive(:new).with(connection).and_return(client)

      described_class.call(channel: channel, max_age: max_age)

      expect(received_calls.size).to eq(1)
      expect(received_calls.first).to contain_exactly("vid1", "vid2", "vid3")
    end

    it "returns API values for the refetched videos" do
      client = instance_double(Channel::Youtube::Client)
      allow(client).to receive(:videos_list).and_return(
        items: [
          make_item("vid1", views: "111", likes: "11", comments: "1"),
          make_item("vid2", views: "222", likes: "22", comments: "2"),
          make_item("vid3", views: "333", likes: "33", comments: "3")
        ]
      )
      allow(Channel::Youtube::Client).to receive(:new).and_return(client)

      result = described_class.call(channel: channel, max_age: max_age)

      expect(result).to eq(
        "vid1" => { views: 111, likes: 11, comments: 1 },
        "vid2" => { views: 222, likes: 22, comments: 2 },
        "vid3" => { views: 333, likes: 33, comments: 3 }
      )
    end

    it "persists the fetched numbers into Pito::Stats with a fresh synced_at" do
      client = instance_double(Channel::Youtube::Client)
      allow(client).to receive(:videos_list).and_return(
        items: [
          make_item("vid1", views: "111", likes: "11", comments: "1"),
          make_item("vid2", views: "222", likes: "22", comments: "2"),
          make_item("vid3", views: "333", likes: "33", comments: "3")
        ]
      )
      allow(Channel::Youtube::Client).to receive(:new).and_return(client)

      cutoff = 1.minute.ago
      described_class.call(channel: channel, max_age: max_age)

      expect(Pito::Stats.get(video1, :views)).to eq(111)
      expect(Pito::Stats.get(video1, :likes)).to eq(11)
      expect(Pito::Stats.get(video1, :comments)).to eq(1)
      expect(video1.stats.find_by(kind: "likes").synced_at).to be >= cutoff
    end
  end

  # ─── MIXED ──────────────────────────────────────────────────────────────────

  describe "one fresh and one stale video" do
    let!(:fresh_video) { create(:video, channel: channel, youtube_video_id: "fresh_vid") }
    let!(:stale_video) { create(:video, channel: channel, youtube_video_id: "stale_vid") }

    before do
      Pito::Stats.set(fresh_video, :views,    500)
      Pito::Stats.set(fresh_video, :likes,    50)
      Pito::Stats.set(fresh_video, :comments, 5)

      travel_to(4.hours.ago) do
        Pito::Stats.set(stale_video, :views,    1)
        Pito::Stats.set(stale_video, :likes,    1)
        Pito::Stats.set(stale_video, :comments, 1)
      end
    end

    it "only sends the stale id to videos_list, answering the fresh one from the DB" do
      received_calls = []
      client = instance_double(Channel::Youtube::Client)
      allow(client).to receive(:videos_list) do |ids:, parts:|
        received_calls << ids
        { items: [ make_item("stale_vid", views: "999", likes: "99", comments: "9") ] }
      end
      allow(Channel::Youtube::Client).to receive(:new).and_return(client)

      result = described_class.call(channel: channel, max_age: max_age)

      expect(received_calls).to eq([ [ "stale_vid" ] ])
      expect(result).to eq(
        "fresh_vid" => { views: 500, likes: 50, comments: 5 },
        "stale_vid" => { views: 999, likes: 99, comments: 9 }
      )
    end
  end

  # ─── MISSING rows count as stale ───────────────────────────────────────────

  describe "a video with no Pito::Stats rows at all" do
    let!(:video) { create(:video, channel: channel, youtube_video_id: "no_rows_vid") }

    it "is treated as stale and fetched from the API" do
      client = instance_double(Channel::Youtube::Client)
      allow(client).to receive(:videos_list) do |ids:, parts:|
        expect(ids).to eq([ "no_rows_vid" ])
        { items: [ make_item("no_rows_vid", views: "7", likes: "8", comments: "9") ] }
      end
      allow(Channel::Youtube::Client).to receive(:new).and_return(client)

      result = described_class.call(channel: channel, max_age: max_age)

      expect(result).to eq("no_rows_vid" => { views: 7, likes: 8, comments: 9 })
    end
  end

  # ─── ERROR HONESTY ──────────────────────────────────────────────────────────

  describe "when videos_list raises" do
    let!(:stale_video) { create(:video, channel: channel, youtube_video_id: "stale_vid") }

    before do
      travel_to(4.hours.ago) do
        Pito::Stats.set(stale_video, :views,    1)
        Pito::Stats.set(stale_video, :likes,    1)
        Pito::Stats.set(stale_video, :comments, 1)
      end
    end

    it "propagates the error" do
      client = instance_double(Channel::Youtube::Client)
      allow(client).to receive(:videos_list).and_raise(Channel::Youtube::Error, "API exploded")
      allow(Channel::Youtube::Client).to receive(:new).and_return(client)

      expect { described_class.call(channel: channel, max_age: max_age) }
        .to raise_error(Channel::Youtube::Error, "API exploded")
    end

    it "persists nothing for the failed slice — prior rows are unchanged" do
      client = instance_double(Channel::Youtube::Client)
      allow(client).to receive(:videos_list).and_raise(Channel::Youtube::Error, "API exploded")
      allow(Channel::Youtube::Client).to receive(:new).and_return(client)

      expect { described_class.call(channel: channel, max_age: max_age) }
        .to raise_error(Channel::Youtube::Error)

      expect(Pito::Stats.get(stale_video, :views)).to eq(1)
      expect(Pito::Stats.get(stale_video, :likes)).to eq(1)
      expect(Pito::Stats.get(stale_video, :comments)).to eq(1)
    end
  end

  # ─── empty case ─────────────────────────────────────────────────────────────
  #
  # (No nil-youtube_video_id example on purpose: the column is NOT NULL at
  # the DB level, so the service's `.where.not(youtube_video_id: nil)` scope
  # is purely defensive — exercising it would require mutating the schema
  # mid-example, which isn't worth pinning dead code.)

  describe "a channel with no videos" do
    it "returns an empty hash and makes zero calls" do
      expect(Channel::Youtube::Client).not_to receive(:new)

      result = described_class.call(channel: channel, max_age: max_age)

      expect(result).to eq({})
    end
  end
end
