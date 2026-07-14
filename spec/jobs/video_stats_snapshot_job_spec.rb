# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoStatsSnapshotJob, type: :job do
  include ActiveJob::TestHelper

  # ─── helpers ────────────────────────────────────────────────────────────────

  # Build a minimal videos_list response item for a given youtube_video_id.
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

  # Stub `client.videos_list` to return items for the supplied ids.
  # Matches on the :ids key so each batch call can be asserted independently.
  def stub_videos_list(client, items_by_batch)
    allow(client).to receive(:videos_list) do |ids:, parts:|
      matching = items_by_batch.fetch(ids, [])
      { items: matching }
    end
  end

  # ─── shared setup ───────────────────────────────────────────────────────────

  let(:connection)  { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCtest111",
           title: "Test Channel")
  end

  subject(:job) { described_class.new }

  # ─── batching ───────────────────────────────────────────────────────────────

  describe "batching" do
    context "when a channel has 51 videos (> BATCH_SIZE of 50)" do
      let!(:videos) { create_list(:video, 51, channel: channel) }

      it "calls videos_list twice (one call per batch)" do
        received_batches = []

        client = instance_double(Channel::Youtube::Client)
        allow(client).to receive(:videos_list) do |ids:, parts:|
          received_batches << ids
          { items: [] }
        end
        allow(Channel::Youtube::Client).to receive(:new).and_return(client)

        job.perform

        expect(received_batches.size).to eq(2)
      end

      it "first batch contains exactly 50 ids and the second contains 1" do
        received_batches = []

        client = instance_double(Channel::Youtube::Client)
        allow(client).to receive(:videos_list) do |ids:, parts:|
          received_batches << ids
          { items: [] }
        end
        allow(Channel::Youtube::Client).to receive(:new).and_return(client)

        job.perform

        expect(received_batches.map(&:size)).to eq([ 50, 1 ])
      end
    end

    context "when a channel has exactly 50 videos (= BATCH_SIZE)" do
      let!(:videos) { create_list(:video, 50, channel: channel) }

      it "calls videos_list exactly once with all 50 ids" do
        received_batches = []

        client = instance_double(Channel::Youtube::Client)
        allow(client).to receive(:videos_list) do |ids:, parts:|
          received_batches << ids
          { items: [] }
        end
        allow(Channel::Youtube::Client).to receive(:new).and_return(client)

        job.perform

        expect(received_batches.size).to eq(1)
        expect(received_batches.first.size).to eq(50)
      end
    end
  end

  # ─── stats written ───────────────────────────────────────────────────────────

  describe "stats written" do
    let!(:video) { create(:video, channel: channel, youtube_video_id: "vid_stats_1") }

    before do
      client = instance_double(Channel::Youtube::Client)
      allow(Channel::Youtube::Client).to receive(:new).and_return(client)
      allow(client).to receive(:videos_list).and_return(
        { items: [ make_item("vid_stats_1", views: "9999", likes: "42", comments: "7") ] }
      )
    end

    it "writes the view count into Pito::Stats" do
      job.perform
      expect(Pito::Stats.get(video, :views)).to eq(9999)
    end

    it "writes the like count into Pito::Stats" do
      job.perform
      expect(Pito::Stats.get(video, :likes)).to eq(42)
    end

    it "writes the comment count into Pito::Stats" do
      job.perform
      expect(Pito::Stats.get(video, :comments)).to eq(7)
    end

    it "coerces string values to integers" do
      job.perform
      expect(Pito::Stats.get(video, :views)).to be_a(Integer)
    end

    context "when a stat field is absent (nil)" do
      before do
        client = Channel::Youtube::Client.new(connection)
        allow(Channel::Youtube::Client).to receive(:new).and_return(client)
        allow(client).to receive(:videos_list).and_return(
          { items: [ { id: "vid_stats_1", statistics: {} } ] }
        )
      end

      it "defaults missing counts to 0" do
        job.perform
        expect(Pito::Stats.get(video, :views)).to eq(0)
        expect(Pito::Stats.get(video, :likes)).to eq(0)
        expect(Pito::Stats.get(video, :comments)).to eq(0)
      end
    end

    context "when the :statistics key is entirely absent from the response item" do
      before do
        client = instance_double(Channel::Youtube::Client)
        allow(Channel::Youtube::Client).to receive(:new).and_return(client)
        allow(client).to receive(:videos_list).and_return(
          { items: [ { id: "vid_stats_1" } ] }
        )
      end

      it "does not raise" do
        expect { job.perform }.not_to raise_error
      end

      it "writes 0 for all stat fields" do
        job.perform
        expect(Pito::Stats.get(video, :views)).to eq(0)
        expect(Pito::Stats.get(video, :likes)).to eq(0)
        expect(Pito::Stats.get(video, :comments)).to eq(0)
      end
    end
  end

  # ─── skips needs_reauth channels ─────────────────────────────────────────────

  describe "skipping needs_reauth channels" do
    let(:reauth_connection) { create(:youtube_connection, :needs_reauth) }
    let!(:reauth_channel) do
      create(:channel, youtube_connection: reauth_connection, youtube_channel_id: "UCreauth")
    end
    let!(:reauth_video) { create(:video, channel: reauth_channel, youtube_video_id: "reauth_vid") }

    it "does not build a client for a needs_reauth channel" do
      expect(Channel::Youtube::Client).not_to receive(:new)
        .with(reauth_connection)

      # Ensure the normal channel also gets no client (it has no videos in this context)
      allow_any_instance_of(Channel::Youtube::Client).to receive(:videos_list)
        .and_return({ items: [] })

      job.perform
    end

    it "does not write stats for videos on a needs_reauth channel" do
      allow_any_instance_of(Channel::Youtube::Client).to receive(:videos_list)
        .and_return({ items: [] })

      expect { job.perform }.not_to change { Pito::Stats.get(reauth_video, :views) }
    end
  end

  # ─── skips channels with no videos ───────────────────────────────────────────

  describe "skipping channels with no videos" do
    it "does not call videos_list when the channel has no videos" do
      expect_any_instance_of(Channel::Youtube::Client).not_to receive(:videos_list)
      job.perform
    end
  end

  # ─── no connected channels ────────────────────────────────────────────────────

  describe "no connected channels" do
    before { connection.update!(needs_reauth: true) }

    it "does not call videos_list" do
      expect_any_instance_of(Channel::Youtube::Client).not_to receive(:videos_list)
      job.perform
    end

    it "does not raise" do
      expect { job.perform }.not_to raise_error
    end
  end

  # ─── error resilience ────────────────────────────────────────────────────────

  describe "error resilience" do
    let(:connection2) { create(:youtube_connection) }
    let!(:channel2) do
      create(:channel,
             youtube_connection: connection2,
             youtube_channel_id: "UCtest222",
             title: "Other Channel")
    end

    let!(:video1)  { create(:video, channel: channel,  youtube_video_id: "good_vid") }
    let!(:video2)  { create(:video, channel: channel2, youtube_video_id: "other_vid") }

    before do
      # channel's client raises; channel2's client works fine
      bad_client  = instance_double(Channel::Youtube::Client)
      good_client = instance_double(Channel::Youtube::Client)

      allow(Channel::Youtube::Client).to receive(:new).with(connection).and_return(bad_client)
      allow(Channel::Youtube::Client).to receive(:new).with(connection2).and_return(good_client)

      allow(bad_client).to receive(:videos_list).and_raise(StandardError, "API exploded")
      allow(good_client).to receive(:videos_list).and_return(
        { items: [ make_item("other_vid", views: "777", likes: "3", comments: "1") ] }
      )
    end

    it "does not raise even if one channel's client errors" do
      expect { job.perform }.not_to raise_error
    end

    it "logs the error for the failing channel" do
      expect(Rails.logger).to receive(:error)
        .with(/VideoStatsSnapshotJob.*channel=#{channel.id}.*API exploded/)
      job.perform
    end

    it "still writes stats for the channel that succeeded" do
      job.perform
      expect(Pito::Stats.get(video2, :views)).to eq(777)
    end

    # Reported to AppSignal AND isolated — never re-raised, siblings still write.
    it "reports the error to AppSignal without breaking isolation" do
      allow(Appsignal).to receive(:report_error)

      expect { job.perform }.not_to raise_error

      expect(Appsignal).to have_received(:report_error)
        .with(an_instance_of(StandardError).and(having_attributes(message: "API exploded")))
      expect(Pito::Stats.get(video2, :views)).to eq(777)
    end
  end
end
