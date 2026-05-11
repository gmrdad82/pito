require "rails_helper"
require "rake"

# Phase 26 §01g — viewer-time backfill rake task.
RSpec.describe "pito:backfill_viewer_time_buckets", type: :task do
  before(:all) do
    Rake.application.rake_require(
      "tasks/viewer_time_backfill",
      [ Rails.root.join("lib").to_s ]
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["pito:backfill_viewer_time_buckets"] }

  before { task.reenable }

  after { ENV.delete("DAYS") }

  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, youtube_connection: connection) }

  describe "happy path" do
    it "enqueues one VideoViewerTimeSyncJob per owned video with DAYS=90 default" do
      v1 = create(:video, channel: channel)
      v2 = create(:video, channel: channel)

      expect(VideoViewerTimeSyncJob).to receive(:perform_async).with(v1.id, 90).once
      expect(VideoViewerTimeSyncJob).to receive(:perform_async).with(v2.id, 90).once

      expect { task.invoke }.to output(/enqueued 2 viewer-time sync jobs/).to_stdout
    end

    it "respects the DAYS env var" do
      v1 = create(:video, channel: channel)

      ENV["DAYS"] = "7"
      expect(VideoViewerTimeSyncJob).to receive(:perform_async).with(v1.id, 7).once

      expect { task.invoke }.to output(/DAYS=7/).to_stdout
    end
  end

  describe "edge cases" do
    it "no-ops cleanly when there are zero eligible videos" do
      expect(VideoViewerTimeSyncJob).not_to receive(:perform_async)
      expect { task.invoke }.to output(/enqueued 0 viewer-time sync jobs/).to_stdout
    end

    it "supports large DAYS values" do
      v1 = create(:video, channel: channel)
      ENV["DAYS"] = "365"
      expect(VideoViewerTimeSyncJob).to receive(:perform_async).with(v1.id, 365).once
      expect { task.invoke }.to output.to_stdout
    end

    it "aborts on non-positive DAYS" do
      ENV["DAYS"] = "0"
      expect { task.invoke }.to raise_error(SystemExit)
    end

    it "skips videos whose channel has no YouTube connection" do
      orphan_channel = create(:channel)
      _orphan_video = create(:video, channel: orphan_channel)

      expect(VideoViewerTimeSyncJob).not_to receive(:perform_async)
      expect { task.invoke }.to output(/enqueued 0/).to_stdout
    end
  end
end
