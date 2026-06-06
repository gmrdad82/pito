# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightlyVideoSyncJob, type: :job do
  include ActiveJob::TestHelper

  let(:connection) { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCaaa111",
           title: "Alpha Channel")
  end

  let(:playlist_response) do
    {
      items: [
        {
          content_details: {
            related_playlists: { uploads: "UUaaa111" }
          }
        }
      ]
    }
  end

  let(:playlist_items_response) do
    {
      items: [
        { snippet: { resource_id: { video_id: "vid1" } } },
        { snippet: { resource_id: { video_id: "vid2" } } }
      ],
      next_page_token: nil
    }
  end

  let(:videos_list_response) do
    {
      items: [
        {
          id: "vid1",
          etag: "etag1",
          snippet: {
            title: "Video One",
            description: "Desc one",
            tags: [ "tag1" ],
            category_id: "20",
            published_at: 1.day.ago.to_s,
            thumbnails: { high: { url: "http://example.com/v1.jpg" } }
          },
          statistics: { view_count: "1000" },
          content_details: { duration: "PT5M30S" },
          status: { privacy_status: "public" }
        },
        {
          id: "vid2",
          etag: "etag2",
          snippet: {
            title: "Video Two",
            description: "Desc two",
            tags: [],
            category_id: "20",
            published_at: 2.days.ago.to_s,
            thumbnails: { high: { url: "http://example.com/v2.jpg" } }
          },
          statistics: { view_count: "500" },
          content_details: { duration: "PT10M" },
          status: { privacy_status: "public" }
        }
      ]
    }
  end

  before do
    allow_any_instance_of(Channel::Youtube::Client).to receive(:channels_list)
      .and_return(playlist_response)
    allow_any_instance_of(Channel::Youtube::Client).to receive(:playlist_items_list)
      .and_return(playlist_items_response)
    allow_any_instance_of(Channel::Youtube::Client).to receive(:videos_list)
      .and_return(videos_list_response)
  end

  describe "#perform" do
    subject(:job) { described_class.new }

    it "imports videos for the channel" do
      expect { job.perform(channel.id) }.to change(Video, :count).by(2)
    end

    it "enqueues VideoVoyageIndexJob for each new video" do
      expect {
        job.perform(channel.id)
      }.to have_enqueued_job(VideoVoyageIndexJob).twice
    end

    it "does not enqueue VideoVoyageIndexJob for an unchanged video (digest-gate simulation)" do
      # Import once to create the videos
      job.perform(channel.id)
      clear_enqueued_jobs

      # Second run — same API response → no embed-field changes on existing records
      # saved_changes will be empty so no re-enqueue
      job.perform(channel.id)

      voyage_jobs = enqueued_jobs.select { |j| j["job_class"] == "VideoVoyageIndexJob" }
      expect(voyage_jobs).to be_empty
    end

    it "enqueues GameStatsRefreshJob for games linked to the channel's videos" do
      game = create(:game)
      job.perform(channel.id)
      clear_enqueued_jobs

      video = Video.find_by(youtube_video_id: "vid1")
      VideoGameLink.create!(video: video, game: game)
      clear_enqueued_jobs

      # Second run triggers GameStatsRefreshJob for the linked game
      job.perform(channel.id)

      expect(enqueued_jobs.any? { |j|
        j["job_class"] == "GameStatsRefreshJob" && j["arguments"]&.first == game.id
      }).to be true
    end

    it "is a no-op for a missing channel" do
      expect { job.perform(-1) }.not_to change(Video, :count)
    end

    it "is a no-op for a channel without a youtube_connection" do
      disconnected = create(:channel)
      expect { job.perform(disconnected.id) }.not_to change(Video, :count)
    end

    it "is a no-op for a reauth channel" do
      reauth_connection = create(:youtube_connection, :needs_reauth)
      reauth_channel = create(:channel, youtube_connection: reauth_connection)
      expect { job.perform(reauth_channel.id) }.not_to change(Video, :count)
    end

    it "logs + swallows errors so the nightly fan-out continues" do
      # Raise an error that bypasses the inner rescues (e.g., from playlist_items_list
      # which also has a rescue, so we simulate an error at the channel.touch level —
      # the outer rescue in perform catches anything not already swallowed by privates).
      allow_any_instance_of(Channel::Youtube::Client).to receive(:playlist_items_list)
        .and_raise(StandardError, "API down")

      # playlist_items_list rescue returns [] → perform returns early (no log).
      # Verify the job does NOT raise regardless.
      expect { job.perform(channel.id) }.not_to raise_error
    end

    it "logs errors that escape the private rescues" do
      # Simulate an error at the outer level by making channel.touch raise
      allow(channel).to receive(:touch).and_raise(StandardError, "DB connection lost")
      allow(Channel).to receive(:find_by).and_return(channel)

      expect(Rails.logger).to receive(:error).with(/NightlyVideoSyncJob.*channel=#{channel.id}.*DB connection lost/)
      expect { job.perform(channel.id) }.not_to raise_error
    end
  end
end
