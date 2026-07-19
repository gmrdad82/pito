# frozen_string_literal: true

require "rails_helper"

# Wire-level proof for the 2026-07-19 invalidPublishAt production incident.
#
# ROOT CAUSE (see Video#already_published?, app/models/video.rb): YouTube's
# `status.publishAt` is settable only on a vid that is private AND has NEVER
# gone public (developers.google.com/youtube/v3/docs/videos) — pairing
# `privacyStatus: private` with `publishAt` in the SAME PUT does not satisfy
# the "never published" half. The mass-schedule batch that broke in
# production mixed already-public vids in with genuinely-schedulable ones;
# YouTube rejected the former with invalidPublishAt regardless of formatting.
# That guard is covered by Pito::Chat::Handlers::Schedule and
# Pito::Confirmation::Executor specs (stage-time + confirm-time rejection).
#
# THIS spec pins the OTHER half of the investigation: proves the RFC3339
# formatting `Channel::Youtube::VideosClient#youtube_rfc3339` already handled
# was never the defect for an ELIGIBLE vid — the exact `publishAt` string that
# lands in the `Google::Apis::YoutubeV3::VideoStatus` PUT body is correct UTC
# RFC3339 (`...Z`, not `+0200`) end to end: confirmation payload →
# Pito::Confirmation::Executor → VideoRemoteStatusSync →
# Channel::Youtube::VideosClient#update_video, for BOTH the single and the
# mass confirm flow (both enqueue the same job with the same DEFAULT_FIELDS).
RSpec.describe Channel::Youtube::VideosClient, type: :service do
  include ActiveJob::TestHelper

  describe "schedule confirm → VideoRemoteStatusSync → videos.update — wire pin" do
    let(:connection)   { create(:youtube_connection) }
    let!(:channel)     { create(:channel, youtube_connection: connection) }
    let(:conversation) { create(:conversation) }
    let(:svc)          { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    # A realistic `videos.list?part=snippet,status` snapshot — a real gem
    # object (not a bare double), so `.to_h` matches what VideosReader#symbolize
    # actually receives in production (snake_case keys, real attribute types).
    def remote_snapshot_for(video, privacy_status:)
      Google::Apis::YoutubeV3::Video.new(
        id: video.youtube_video_id,
        snippet: Google::Apis::YoutubeV3::VideoSnippet.new(
          title: video.title, description: "d", tags: [], category_id: "20"
        ),
        status: Google::Apis::YoutubeV3::VideoStatus.new(
          privacy_status: privacy_status, publish_at: nil,
          self_declared_made_for_kids: false, embeddable: true,
          public_stats_viewable: true, license: "youtube"
        )
      )
    end

    before do
      allow(Channel::Youtube::ServiceFactory).to receive(:data_service).with(connection).and_return(svc)
      allow(svc).to receive(:update_video)
    end

    context "single confirm (confirm_video_schedule)" do
      let!(:video) do
        create(:video, channel: channel, privacy_status: :private, publish_at: nil, youtube_video_id: "yt_wire_single")
      end

      it "PUTs part=status ALONE with privacyStatus private and publishAt as UTC RFC3339 Z" do
        allow(svc).to receive(:list_videos)
          .and_return(double(items: [ remote_snapshot_for(video, privacy_status: "private") ]))

        Time.use_zone("Europe/Madrid") do
          payload = Pito::MessageBuilder::Video::ScheduleConfirmation.call(
            video, conversation: conversation, when: Time.zone.local(2026, 7, 20, 20, 0)
          )
          Pito::Confirmation::Executor.confirm("video_schedule", payload)
        end

        perform_enqueued_jobs

        expect(svc).to have_received(:update_video) do |parts, body|
          expect(parts).to eq("status")
          expect(body.snippet).to be_nil
          expect(body.status.privacy_status).to eq("private")
          # 20:00 Europe/Madrid in July (CEST, UTC+2) → 18:00 UTC.
          expect(body.status.publish_at).to eq("2026-07-20T18:00:00Z")
          expect(body.status.to_json).to include('"publishAt":"2026-07-20T18:00:00Z"')
        end
      end
    end

    context "mass confirm (confirm_video_schedule_mass)" do
      let!(:video1) do
        create(:video, channel: channel, title: "Mass Wire One", privacy_status: :private,
                       publish_at: nil, youtube_video_id: "yt_wire_mass_1")
      end
      let!(:video2) do
        create(:video, channel: channel, title: "Mass Wire Two", privacy_status: :private,
                       publish_at: nil, youtube_video_id: "yt_wire_mass_2")
      end

      it "PUTs the correct UTC RFC3339 publishAt for EVERY item in the batch" do
        allow(svc).to receive(:list_videos) do |_parts, id:|
          video = id == "yt_wire_mass_1" ? video1 : video2
          double(items: [ remote_snapshot_for(video, privacy_status: "private") ])
        end

        # Collect every videos.update call (one per vid) instead of relying on
        # have_received(...).with(...) { block } — that combination asserts
        # against the wrong invocation when the same message fires more than
        # once with different args.
        calls = []
        allow(svc).to receive(:update_video) { |parts, body| calls << [ parts, body ] }

        Time.use_zone("Europe/Madrid") do
          payload = Pito::MessageBuilder::Video::MassScheduleConfirmation.call(
            [
              { video: video1, publish_at: Time.zone.local(2026, 7, 20, 20, 0) },
              { video: video2, publish_at: Time.zone.local(2026, 7, 21, 12, 0) }
            ],
            conversation: conversation
          )
          Pito::Confirmation::Executor.confirm("video_schedule_mass", payload)
        end

        perform_enqueued_jobs

        expect(calls.size).to eq(2)
        parts1, body1 = calls.find { |_parts, body| body.id == "yt_wire_mass_1" }
        parts2, body2 = calls.find { |_parts, body| body.id == "yt_wire_mass_2" }

        expect(parts1).to eq("status")
        expect(body1.status.privacy_status).to eq("private")
        # 20:00 Europe/Madrid in July (CEST, UTC+2) → 18:00 UTC.
        expect(body1.status.publish_at).to eq("2026-07-20T18:00:00Z")

        expect(parts2).to eq("status")
        expect(body2.status.privacy_status).to eq("private")
        # 12:00 Europe/Madrid in July (CEST, UTC+2) → 10:00 UTC.
        expect(body2.status.publish_at).to eq("2026-07-21T10:00:00Z")
      end
    end

    context "rejection-notification path stays intact" do
      let!(:video) do
        create(:video, channel: channel, privacy_status: :private, publish_at: nil, youtube_video_id: "yt_wire_reject")
      end

      it "still surfaces a sync_rejected Notification when YouTube rejects an otherwise-eligible PUT" do
        allow(svc).to receive(:list_videos)
          .and_return(double(items: [ remote_snapshot_for(video, privacy_status: "private") ]))
        allow(svc).to receive(:update_video)
          .and_raise(Google::Apis::ClientError.new("invalidPublishAt", status_code: 400))

        Time.use_zone("Europe/Madrid") do
          payload = Pito::MessageBuilder::Video::ScheduleConfirmation.call(
            video, conversation: conversation, when: Time.zone.local(2026, 7, 20, 20, 0)
          )
          Pito::Confirmation::Executor.confirm("video_schedule", payload)
        end

        expect { perform_enqueued_jobs }.to change(Notification, :count).by(1)
        expect(Notification.last.message).to include(video.title)
        expect(Notification.last.level).to eq("error")
      end
    end
  end
end
