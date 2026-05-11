require "rails_helper"

# Phase 26 §01g — daily fan-out job spec.
RSpec.describe ViewerTimeDailyRefreshJob do
  let(:user) { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) { create(:channel, youtube_connection: connection) }

  describe "#perform" do
    it "enqueues VideoViewerTimeSyncJob once per owned video" do
      v1 = create(:video, channel: channel)
      v2 = create(:video, channel: channel)

      expect(VideoViewerTimeSyncJob).to receive(:perform_async).with(v1.id).once
      expect(VideoViewerTimeSyncJob).to receive(:perform_async).with(v2.id).once

      described_class.new.perform
    end

    it "skips videos belonging to a channel without a youtube_connection" do
      orphan_channel = create(:channel)
      orphan_video = create(:video, channel: orphan_channel)

      expect(VideoViewerTimeSyncJob).not_to receive(:perform_async).with(orphan_video.id)

      described_class.new.perform
    end

    it "skips videos when the underlying connection needs reauth" do
      reauth_connection = create(:youtube_connection, user: user, needs_reauth: true)
      reauth_channel = create(:channel, youtube_connection: reauth_connection)
      reauth_video = create(:video, channel: reauth_channel)

      expect(VideoViewerTimeSyncJob).not_to receive(:perform_async).with(reauth_video.id)

      described_class.new.perform
    end

    it "no-ops cleanly when there are zero eligible videos" do
      expect {
        described_class.new.perform
      }.not_to raise_error
    end
  end
end
