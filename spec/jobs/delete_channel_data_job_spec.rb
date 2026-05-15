require "rails_helper"

RSpec.describe DeleteChannelDataJob, type: :job do
  before do
    # Suppress any auto-enqueued ChannelSync jobs from `after_create_commit`
    # callbacks that would otherwise queue real work in the test runner.
    Sidekiq::Testing.fake!
    ChannelSync.clear
  end

  let(:connection) { create(:youtube_connection) }
  let!(:channel) { create(:channel, youtube_connection: connection) }

  describe "#perform — happy path full cascade" do
    let!(:video_a) { create(:video, channel: channel) }
    let!(:video_b) { create(:video, channel: channel) }
    let!(:video_c) { create(:video, channel: channel) }

    before do
      # Channel-level dependents.
      create(:channel_daily, channel: channel, date: Date.current)
      create(:channel_window_summary, channel: channel,
                                      window: "7d",
                                      window_start: 7.days.ago.to_date,
                                      window_end: Date.current)
      create(:channel_change_log, channel: channel)
      create(:rejected_video_import, channel: channel)
      # Video-level dependents across two videos to exercise the
      # transitive cascade.
      create(:video_daily, video: video_a, date: Date.current)
      create(:video_daily, video: video_b, date: Date.current)
      create(:video_window_summary, video: video_a, window: "7d",
                                    window_start: 7.days.ago.to_date,
                                    window_end: Date.current)
      create(:video_diff, video: video_a)
      create(:video_change_log, video: video_b)
      game = create(:game)
      create(:video_game_link, video: video_a, game: game)
    end

    it "destroys the channel and every dependent row" do
      described_class.new.perform(channel.id, connection.id)

      expect(Channel.where(id: channel.id)).not_to exist
      expect(Video.where(channel_id: channel.id)).not_to exist
      expect(ChannelDaily.where(channel_id: channel.id)).not_to exist
      expect(ChannelWindowSummary.where(channel_id: channel.id)).not_to exist
      expect(ChannelChangeLog.where(channel_id: channel.id)).not_to exist
      expect(RejectedVideoImport.where(channel_id: channel.id)).not_to exist

      # Video-side checks — every video_id under the destroyed channel
      # is gone.
      video_ids = [ video_a.id, video_b.id, video_c.id ]
      expect(VideoDaily.where(video_id: video_ids)).not_to exist
      expect(VideoWindowSummary.where(video_id: video_ids)).not_to exist
      expect(VideoDiff.where(video_id: video_ids)).not_to exist
      expect(VideoChangeLog.where(video_id: video_ids)).not_to exist
      expect(VideoGameLink.where(video_id: video_ids)).not_to exist
    end

    it "sweeps every video_* analytics table for orphan rows" do
      described_class.new.perform(channel.id, connection.id)

      video_ids_before = [ video_a.id, video_b.id, video_c.id ]
      # Explicit per-table sweep — a new analytics table forgotten in
      # the cascade fails this test loud.
      [
        VideoDaily, VideoDailyByCountry, VideoDailyByDeviceType,
        VideoDailyByOperatingSystem, VideoDailyByTrafficSource,
        VideoDailyBySubscribedStatus, VideoDailyByAgeGroupGender,
        VideoWindowSummary, VideoRetention
      ].each do |klass|
        expect(klass.where(video_id: video_ids_before).count)
          .to eq(0), "Expected zero #{klass.name} rows after revoke"
      end
    end
  end

  describe "YoutubeConnection cleanup branches" do
    it "destroys the connection when the revoked channel was its only channel and no orphan videos exist" do
      described_class.new.perform(channel.id, connection.id)
      expect(YoutubeConnection.where(id: connection.id)).not_to exist
    end

    it "preserves the connection when another channel still references it" do
      other_channel = create(:channel, youtube_connection: connection)
      described_class.new.perform(channel.id, connection.id)

      expect(YoutubeConnection.where(id: connection.id)).to exist
      expect(Channel.where(id: other_channel.id)).to exist
    end

    it "preserves the connection when orphan videos still reference it (nullify guard)" do
      # Channel-less video that still carries the connection FK. Phase
      # 7C disconnect-lifecycle: videos outlive their channel via
      # `dependent: :nullify` on the YoutubeConnection→videos
      # association. Such a video preserves the connection in this
      # cleanup branch.
      Video.create!(channel: create(:channel),
                    youtube_connection_id: connection.id,
                    youtube_video_id: "orphan_vid_xyz",
                    title: "orphan", description: "x",
                    category_id: "20", privacy_status: :private)

      described_class.new.perform(channel.id, connection.id)
      expect(YoutubeConnection.where(id: connection.id)).to exist
    end

    it "is a no-op on the connection when the channel has no connection" do
      bare_channel = create(:channel) # no youtube_connection
      described_class.new.perform(bare_channel.id, nil)
      # No error raised. Channel is gone.
      expect(Channel.where(id: bare_channel.id)).not_to exist
    end
  end

  describe "idempotency" do
    it "is a no-op when run twice with the same channel_id" do
      described_class.new.perform(channel.id, connection.id)
      # Second run — channel already gone, connection already gone.
      expect {
        described_class.new.perform(channel.id, connection.id)
      }.not_to raise_error
    end

    it "is a no-op when the channel_id does not exist" do
      expect {
        described_class.new.perform(9_999_999_999, nil)
      }.not_to raise_error
    end

    it "still runs the connection cleanup when channel_id is gone but snapshot exists" do
      lone_connection = create(:youtube_connection) # no channels under it
      # No channel; cleanup branch should destroy the connection
      # because there are no channels and no videos referencing it.
      described_class.new.perform(9_999_999_999, lone_connection.id)
      expect(YoutubeConnection.where(id: lone_connection.id)).not_to exist
    end
  end

  describe "other channels untouched" do
    let!(:other_channel) { create(:channel, youtube_connection: connection) }
    let!(:other_video) { create(:video, channel: other_channel) }

    before do
      create(:video_daily, video: other_video, date: Date.current)
    end

    it "leaves the second channel's videos and analytics untouched" do
      described_class.new.perform(channel.id, connection.id)

      expect(Channel.where(id: other_channel.id)).to exist
      expect(Video.where(id: other_video.id)).to exist
      expect(VideoDaily.where(video_id: other_video.id)).to exist
    end

    it "preserves the connection (second channel keeps it alive)" do
      described_class.new.perform(channel.id, connection.id)
      expect(YoutubeConnection.where(id: connection.id)).to exist
    end
  end

  describe "args contract" do
    it "accepts (channel_id, connection_id_snapshot) in that order" do
      expect {
        described_class.new.perform(channel.id, connection.id)
      }.not_to raise_error
    end

    it "accepts (channel_id, nil) and reads connection id from the channel" do
      described_class.new.perform(channel.id, nil)
      # The connection should be destroyed since the channel had it.
      expect(YoutubeConnection.where(id: connection.id)).not_to exist
    end
  end

  describe "sidekiq options" do
    it "is registered with retry: 3 on the default queue" do
      opts = described_class.sidekiq_options
      expect(opts["retry"]).to eq(3)
      expect(opts["queue"]).to eq("default")
    end
  end
end
