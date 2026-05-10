require "rails_helper"

RSpec.describe NotificationSource::VideoPrePublishCheckMissed do
  let(:channel) { create(:channel) }
  let(:video) do
    create(:video, channel: channel,
                   privacy_status: :public,
                   published_at: 1.hour.ago,
                   pre_publish_checked_at: nil,
                   title: "test video",
                   pre_publish_game_ok: false,
                   pre_publish_age_ok: true,
                   pre_publish_paid_promotion_ok: false,
                   pre_publish_end_screen_ok: false)
  end

  describe ".report!" do
    it "inserts a row with severity :info and event_type video_pre_publish_check_missed" do
      n = described_class.report!(video)
      expect(n).to be_persisted
      expect(n.event_type).to eq("video_pre_publish_check_missed")
      expect(n.info?).to be(true)
    end

    it "uses dedup_key 'missed-check-{id}'" do
      n = described_class.report!(video)
      expect(n.dedup_key).to eq("missed-check-#{video.id}")
    end

    it "is idempotent on a second call" do
      n1 = described_class.report!(video)
      expect {
        n2 = described_class.report!(video)
        expect(n2.id).to eq(n1.id)
      }.not_to change(Notification, :count)
    end

    it "stores video.title in event_payload" do
      n = described_class.report!(video)
      expect(n.event_payload["video_title"]).to eq("test video")
      expect(n.event_payload["video_id"]).to eq(video.id)
    end

    it "stores the missing-checks list" do
      n = described_class.report!(video)
      expect(n.event_payload["missing_checks"]).to match_array(%w[game paid_promotion end_screen])
    end

    it "points url at the video edit page" do
      n = described_class.report!(video)
      expect(n.url).to eq("/videos/#{video.id}/edit")
    end

    it "produces distinct rows for different videos" do
      v2 = create(:video, channel: channel, privacy_status: :public,
                          published_at: 1.hour.ago)
      n1 = described_class.report!(video)
      n2 = described_class.report!(v2)
      expect(n1.id).not_to eq(n2.id)
    end
  end
end
