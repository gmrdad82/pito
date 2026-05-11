require "rails_helper"

RSpec.describe VideoDiffCheckJob, type: :job do
  let(:user) { create(:user) }
  let(:youtube_connection) { create(:youtube_connection, user: user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: youtube_connection)
  end
  let(:video) do
    create(:video, channel: channel, title: "local title",
                   description: "local body",
                   self_declared_made_for_kids: false,
                   contains_synthetic_media: false,
                   embeddable: true, public_stats_viewable: true,
                   view_count: 0, like_count: 0, comment_count: 0,
                   duration_seconds: 60,
                   thumbnail_url: "https://i.ytimg.com/vi/abc/maxres.jpg",
                   published_at: nil)
  end

  let(:identical_payload) do
    {
      items: [
        {
          snippet: { title: video.title, description: video.description,
                     tags: video.tags || [], categoryId: video.category_id,
                     thumbnails: { maxres: { url: video.thumbnail_url } } },
          status: { privacyStatus: "private", publishAt: nil,
                    embeddable: true,
                    publicStatsViewable: true,
                    selfDeclaredMadeForKids: false,
                    containsSyntheticMedia: false,
                    madeForKids: false },
          statistics: { viewCount: video.view_count.to_s,
                        likeCount: video.like_count.to_s,
                        commentCount: video.comment_count.to_s },
          contentDetails: { duration: "PT1M" }
        }
      ]
    }
  end

  let(:diff_payload) do
    payload = identical_payload.deep_dup
    payload[:items].first[:snippet][:title] = "remote title"
    payload
  end

  let(:client_double) { instance_double(Youtube::Client) }

  before do
    allow(Youtube::Client).to receive(:new).with(youtube_connection).and_return(client_double)
  end

  describe "happy: no diff" do
    before do
      allow(client_double).to receive(:videos_list).and_return(identical_payload)
    end

    it "does not insert a VideoDiff row" do
      expect {
        described_class.new.perform(video.id)
      }.not_to change(VideoDiff, :count)
    end

    it "does not emit a Notification" do
      expect {
        described_class.new.perform(video.id)
      }.not_to change(Notification, :count)
    end

    it "stamps last_diff_checked_at" do
      described_class.new.perform(video.id)
      expect(video.reload.last_diff_checked_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "happy: single-field diff" do
    before do
      allow(client_double).to receive(:videos_list).and_return(diff_payload)
    end

    it "creates one VideoDiff row with the title field" do
      expect {
        described_class.new.perform(video.id)
      }.to change(VideoDiff, :count).by(1)

      diff = VideoDiff.last
      expect(diff.fields).to include("title")
      expect(diff.payload["title"]).to eq({ "pito" => "local title", "youtube" => "remote title" })
    end

    it "emits a Notification with kind: video_diff_detected" do
      expect {
        described_class.new.perform(video.id)
      }.to change(Notification.where(kind: :video_diff_detected), :count).by(1)
    end

    it "stamps last_diff_checked_at" do
      described_class.new.perform(video.id)
      expect(video.reload.last_diff_checked_at).to be_within(2.seconds).of(Time.current)
    end

    it "is idempotent on re-run (replaces the open diff payload)" do
      described_class.new.perform(video.id)
      expect {
        described_class.new.perform(video.id)
      }.not_to change(VideoDiff, :count)
    end
  end

  describe "sad: video not found" do
    it "logs a warning and returns without raising" do
      expect(Rails.logger).to receive(:warn).with(/video#999999 not found/)
      expect {
        described_class.new.perform(999_999)
      }.not_to raise_error
    end
  end

  describe "sad: channel has no youtube_connection" do
    let(:lonely_channel) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuw",
             youtube_connection: nil)
    end
    let(:lonely_video) { create(:video, channel: lonely_channel) }

    it "logs a warning and returns without making any API call" do
      expect(Youtube::Client).not_to receive(:new)
      expect(Rails.logger).to receive(:warn).with(/has no youtube_connection/)
      described_class.new.perform(lonely_video.id)
    end

    it "does not write a VideoDiff" do
      expect {
        described_class.new.perform(lonely_video.id)
      }.not_to change(VideoDiff, :count)
    end
  end

  describe "sad: connection needs re-auth" do
    before do
      youtube_connection.update_columns(needs_reauth: true)
    end

    it "skips the video with a warning" do
      expect(Youtube::Client).not_to receive(:new)
      expect(Rails.logger).to receive(:warn).with(/needs re-auth/)
      described_class.new.perform(video.id)
    end
  end

  describe "sad: YouTube response has no items (video removed)" do
    before do
      allow(client_double).to receive(:videos_list).and_return(items: [])
    end

    it "logs and returns without creating a diff" do
      expect(Rails.logger).to receive(:warn).with(/not found on YouTube/)
      expect {
        described_class.new.perform(video.id)
      }.not_to change(VideoDiff, :count)
    end
  end

  describe "sad: quota exhausted" do
    before do
      allow(client_double).to receive(:videos_list)
        .and_raise(Youtube::QuotaExhaustedError.new("daily quota"))
    end

    it "re-raises so Sidekiq retries with backoff" do
      expect {
        described_class.new.perform(video.id)
      }.to raise_error(Youtube::QuotaExhaustedError)
    end
  end
end
