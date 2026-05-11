require "rails_helper"

# Phase 22 §6.2 — Channels::VideoImporter.
#
# Drives the playlist walk + diff + Video creation seam. Tests stub
# the `playlist_client:` collaborator so no live wire is touched.
RSpec.describe Channels::VideoImporter, type: :service do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection) }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:import_job) do
    ImportJob.create!(channel: channel, enqueued_by: user, status: :running,
                      started_at: 1.minute.ago)
  end

  # Tiny fake client — enumerates a fixed list of pages.
  class StubPlaylistClient
    def initialize(uploads_playlist_id:, pages: [])
      @uploads_playlist_id = uploads_playlist_id
      @pages = pages.dup
    end

    def uploads_playlist_id(channel:)
      @uploads_playlist_id
    end

    def list_page(playlist_id:, page_token: nil)
      raise "unexpected playlist_id #{playlist_id}" unless playlist_id == @uploads_playlist_id
      @pages.shift || { items: [], next_page_token: nil }
    end
  end

  def yt_id(suffix)
    suffix = suffix.to_s
    suffix + ("A" * (11 - suffix.size))
  end

  describe "happy path" do
    it "creates Video rows for new ids and yields progress per page" do
      client = StubPlaylistClient.new(
        uploads_playlist_id: "UUtest",
        pages: [
          {
            items: [
              { youtube_video_id: yt_id("v1"), title: "Video One", category_id: "20", duration_seconds: 120 },
              { youtube_video_id: yt_id("v2"), title: "Video Two", category_id: "20", duration_seconds: 240 }
            ],
            next_page_token: "page2"
          },
          {
            items: [
              { youtube_video_id: yt_id("v3"), title: "Video Three", category_id: "10", duration_seconds: 60 }
            ],
            next_page_token: nil
          }
        ]
      )

      progress_events = []
      described_class.new(playlist_client: client).call(channel: channel, import_job: import_job) do |progress|
        progress_events << progress
      end

      expect(channel.videos.count).to eq(3)
      expect(channel.videos.pluck(:youtube_video_id)).to contain_exactly(yt_id("v1"), yt_id("v2"), yt_id("v3"))
      import_job.reload
      expect(import_job.imported_videos).to eq(3)
      expect(import_job.total_videos).to eq(3)

      expect(progress_events.length).to eq(2)
      expect(progress_events.last.total).to eq(3)
      expect(progress_events.last.imported).to eq(3)
    end
  end

  describe "diff against existing videos" do
    it "skips videos that already exist for the channel" do
      existing = create(:video, channel: channel, youtube_video_id: yt_id("dup"))

      client = StubPlaylistClient.new(
        uploads_playlist_id: "UUtest",
        pages: [
          {
            items: [
              { youtube_video_id: existing.youtube_video_id, title: "dup" },
              { youtube_video_id: yt_id("new"), title: "new" }
            ],
            next_page_token: nil
          }
        ]
      )

      described_class.new(playlist_client: client).call(channel: channel, import_job: import_job)
      import_job.reload
      expect(channel.videos.count).to eq(2)
      expect(import_job.imported_videos).to eq(1)
      expect(import_job.total_videos).to eq(2)
    end
  end

  describe "diff against rejected_video_imports" do
    it "skips ids that appear in the tombstone table" do
      create(:rejected_video_import,
             channel: channel,
             rejected_by: user,
             youtube_video_id: yt_id("rj"))

      client = StubPlaylistClient.new(
        uploads_playlist_id: "UUtest",
        pages: [
          {
            items: [
              { youtube_video_id: yt_id("rj"), title: "rejected" },
              { youtube_video_id: yt_id("ok"), title: "ok" }
            ],
            next_page_token: nil
          }
        ]
      )

      described_class.new(playlist_client: client).call(channel: channel, import_job: import_job)
      import_job.reload
      expect(channel.videos.pluck(:youtube_video_id)).to contain_exactly(yt_id("ok"))
      expect(import_job.imported_videos).to eq(1)
    end
  end

  describe "channel without an uploads playlist" do
    it "raises FatalError with code :no_uploads_playlist" do
      client = StubPlaylistClient.new(uploads_playlist_id: nil)
      expect {
        described_class.new(playlist_client: client).call(channel: channel, import_job: import_job)
      }.to raise_error(Channels::VideoImporter::FatalError) do |err|
        expect(err.code).to eq(:no_uploads_playlist)
        expect(err.suppress_retry?).to be(true)
      end
    end
  end

  describe "channel missing youtube_connection" do
    it "raises FatalError with code :channel_missing_connection" do
      bare_channel = create(:channel)
      client = StubPlaylistClient.new(uploads_playlist_id: "UUany")
      expect {
        described_class.new(playlist_client: client).call(channel: bare_channel, import_job: import_job)
      }.to raise_error(Channels::VideoImporter::FatalError) do |err|
        expect(err.code).to eq(:channel_missing_connection)
      end
    end
  end

  describe "transient errors propagate" do
    it "lets a TransientError raised by the client bubble" do
      flaky_client = Class.new do
        def uploads_playlist_id(channel:)
          "UUtest"
        end

        def list_page(playlist_id:, page_token: nil)
          raise Channels::VideoImporter::TransientError.new(code: :rate_limited, message: "429")
        end
      end.new

      expect {
        described_class.new(playlist_client: flaky_client).call(channel: channel, import_job: import_job)
      }.to raise_error(Channels::VideoImporter::TransientError) do |err|
        expect(err.code).to eq(:rate_limited)
      end
    end
  end

  describe "partial pagination" do
    it "creates rows for each successful page and stops at the last page" do
      client = StubPlaylistClient.new(
        uploads_playlist_id: "UUtest",
        pages: [
          { items: [ { youtube_video_id: yt_id("p1"), title: "p1" } ], next_page_token: "next" },
          { items: [ { youtube_video_id: yt_id("p2"), title: "p2" } ], next_page_token: nil }
        ]
      )
      described_class.new(playlist_client: client).call(channel: channel, import_job: import_job)
      expect(channel.videos.count).to eq(2)
    end
  end

  describe "counter math under concurrent updates" do
    it "uses atomic SQL increments so a stale in-memory copy does not clobber" do
      client = StubPlaylistClient.new(
        uploads_playlist_id: "UUtest",
        pages: [
          { items: [ { youtube_video_id: yt_id("c1"), title: "c1" } ], next_page_token: nil }
        ]
      )

      # Mutate the row out-of-band BEFORE the service calls reload.
      ImportJob.where(id: import_job.id).update_all(failed_videos: 7)

      described_class.new(playlist_client: client).call(channel: channel, import_job: import_job)
      import_job.reload
      expect(import_job.failed_videos).to eq(7) # not clobbered
      expect(import_job.imported_videos).to eq(1)
      expect(import_job.total_videos).to eq(1)
    end
  end
end
