require "rails_helper"

# Phase 7.5 §11i — ChannelDiffCheckJob.
RSpec.describe ChannelDiffCheckJob, type: :job do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           title: "Local Title",
           description: "Local Description",
           country: "US",
           default_language: "en",
           keywords: "tag1 tag2",
           subscriber_count: 100,
           view_count: 1000,
           video_count: 10,
           youtube_connection: connection)
  end
  let(:client) { instance_double(Youtube::Client) }

  let(:identical_payload) do
    {
      title: channel.title,
      handle: channel.handle,
      description: channel.description,
      country: channel.country,
      default_language: channel.default_language,
      keywords: channel.keywords,
      banner_url: channel.banner_url,
      avatar_url: channel.avatar_url,
      watermark_url: channel.watermark_url,
      watermark_timing: channel.watermark_timing,
      watermark_offset_ms: channel.watermark_offset_ms,
      links: channel.links,
      subscriber_count: 200,
      view_count: 2000,
      video_count: 12,
      hidden_subscriber_count: false,
      published_at: "2020-01-01T00:00:00Z"
    }
  end

  let(:diff_payload) do
    identical_payload.merge(title: "Remote Title")
  end

  before do
    allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
  end

  describe "happy: single-channel mode, no diff" do
    before do
      allow(client).to receive(:fetch_channel).with(channel).and_return(identical_payload)
    end

    it "does not insert a ChannelDiff row" do
      expect {
        described_class.new.perform(channel.id)
      }.not_to change(ChannelDiff, :count)
    end

    it "does not emit a Notification" do
      expect {
        described_class.new.perform(channel.id)
      }.not_to change(Notification, :count)
    end

    it "refreshes the silent statistics columns" do
      described_class.new.perform(channel.id)
      channel.reload
      expect(channel.subscriber_count).to eq(200)
      expect(channel.view_count).to eq(2000)
      expect(channel.video_count).to eq(12)
    end
  end

  describe "happy: single-channel mode, single-field diff" do
    before do
      allow(client).to receive(:fetch_channel).with(channel).and_return(diff_payload)
    end

    it "creates one ChannelDiff row with the title field" do
      expect {
        described_class.new.perform(channel.id)
      }.to change(ChannelDiff, :count).by(1)

      diff = ChannelDiff.last
      expect(diff.fields).to include("title")
      expect(diff.field_diffs["title"]).to eq(
        { "pito" => "Local Title", "youtube" => "Remote Title" }
      )
    end

    it "emits a Notification of kind channel_diff_detected" do
      expect {
        described_class.new.perform(channel.id)
      }.to change(Notification.where(kind: :channel_diff_detected), :count).by(1)
    end

    it "is idempotent on re-run (replaces the open diff payload)" do
      described_class.new.perform(channel.id)
      expect {
        described_class.new.perform(channel.id)
      }.not_to change(ChannelDiff, :count)
    end
  end

  describe "happy: single-channel mode, multi-field diff" do
    let(:multi_payload) do
      identical_payload.merge(
        title: "Remote Title",
        description: "Remote Description",
        country: "GB"
      )
    end

    before do
      allow(client).to receive(:fetch_channel).with(channel).and_return(multi_payload)
    end

    it "creates one diff row with three fields" do
      described_class.new.perform(channel.id)
      diff = ChannelDiff.last
      expect(diff.fields).to match_array(%w[title description country])
    end

    it "emits exactly one notification" do
      expect {
        described_class.new.perform(channel.id)
      }.to change(Notification, :count).by(1)
    end
  end

  describe "happy: cron mode iterates connected channels" do
    let!(:other_connection) { create(:youtube_connection, user: user) }
    let!(:other_channel) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuw",
             title: "Other Local",
             handle: channel.handle,
             description: channel.description,
             country: channel.country,
             default_language: channel.default_language,
             keywords: channel.keywords,
             youtube_connection: other_connection)
    end
    let!(:disconnected) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstux",
             youtube_connection: nil)
    end
    let(:other_client) { instance_double(Youtube::Client) }

    before do
      allow(Youtube::Client).to receive(:new).with(other_connection).and_return(other_client)
      allow(client).to receive(:fetch_channel).with(channel).and_return(diff_payload)
      allow(other_client).to receive(:fetch_channel).with(other_channel).and_return(
        identical_payload.merge(title: "Other Local") # no diff
      )
    end

    it "creates one diff row (for the diffing channel only)" do
      expect {
        described_class.new.perform
      }.to change(ChannelDiff, :count).by(1)
      diff = ChannelDiff.last
      expect(diff.channel_id).to eq(channel.id)
    end

    it "skips channels with no youtube_connection_id (no API call)" do
      expect(Youtube::Client).not_to receive(:new).with(nil)
      described_class.new.perform
    end

    it "emits exactly one notification (only the diffing channel)" do
      expect {
        described_class.new.perform
      }.to change(Notification, :count).by(1)
    end
  end

  describe "sad: existing open diff, same field set → no new notification (dedupe Q1)" do
    let!(:existing) do
      create(:channel_diff, channel: channel, field_diffs: {
        "title" => { "pito" => "Local Title", "youtube" => "Older Remote Title" }
      })
    end

    before do
      allow(client).to receive(:fetch_channel).with(channel).and_return(diff_payload)
    end

    it "refreshes the existing row's field_diffs (no new row)" do
      expect {
        described_class.new.perform(channel.id)
      }.not_to change(ChannelDiff, :count)
      expect(existing.reload.field_diffs["title"]["youtube"]).to eq("Remote Title")
    end

    it "does NOT emit a duplicate notification" do
      expect {
        described_class.new.perform(channel.id)
      }.not_to change(Notification, :count)
    end
  end

  describe "sad: existing open diff, expanded field set → new notification" do
    let!(:existing) do
      create(:channel_diff, channel: channel, field_diffs: {
        "title" => { "pito" => "Local Title", "youtube" => "Remote Title" }
      })
    end

    let(:expanded_payload) do
      identical_payload.merge(title: "Remote Title", description: "Remote Description")
    end

    before do
      allow(client).to receive(:fetch_channel).with(channel).and_return(expanded_payload)
    end

    it "emits a new notification for the expansion" do
      expect {
        described_class.new.perform(channel.id)
      }.to change(Notification.where(kind: :channel_diff_detected), :count).by(1)
    end

    it "refreshes the row with the expanded field set" do
      described_class.new.perform(channel.id)
      expect(existing.reload.fields).to match_array(%w[title description])
    end
  end

  describe "sad: existing open diff, no diff this pass → auto-close" do
    let!(:existing) { create(:channel_diff, channel: channel) }

    before do
      allow(client).to receive(:fetch_channel).with(channel).and_return(identical_payload)
    end

    it "auto-closes the prior row" do
      described_class.new.perform(channel.id)
      existing.reload
      expect(existing).to be_resolved
      expect(existing.resolution_payload).to eq({ "auto_closed" => true })
    end

    it "does NOT emit a notification on the auto-close pass" do
      expect {
        described_class.new.perform(channel.id)
      }.not_to change(Notification, :count)
    end
  end

  describe "edge: TransientError on one of three channels (cron mode)" do
    let!(:c2_connection) { create(:youtube_connection, user: user) }
    let!(:c2) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuw",
             title: "C2 local",
             handle: channel.handle,
             description: channel.description,
             country: channel.country,
             default_language: channel.default_language,
             keywords: channel.keywords,
             youtube_connection: c2_connection)
    end
    let!(:c3_connection) { create(:youtube_connection, user: user) }
    let!(:c3) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstux",
             title: "C3 local",
             handle: channel.handle,
             description: channel.description,
             country: channel.country,
             default_language: channel.default_language,
             keywords: channel.keywords,
             youtube_connection: c3_connection)
    end
    let(:c2_client) { instance_double(Youtube::Client) }
    let(:c3_client) { instance_double(Youtube::Client) }

    before do
      allow(Youtube::Client).to receive(:new).with(c2_connection).and_return(c2_client)
      allow(Youtube::Client).to receive(:new).with(c3_connection).and_return(c3_client)
      allow(client).to receive(:fetch_channel).with(channel).and_return(diff_payload)
      allow(c2_client).to receive(:fetch_channel).with(c2).and_raise(
        Youtube::TransientError.new("temporary blip")
      )
      allow(c3_client).to receive(:fetch_channel).with(c3).and_return(
        identical_payload.merge(title: "C3 local") # no diff
      )
    end

    it "logs and skips the broken channel but continues the iteration" do
      expect(Rails.logger).to receive(:warn).at_least(:once).with(/transient/i)
      expect {
        described_class.new.perform
      }.to change(ChannelDiff, :count).by(1)
    end
  end

  describe "edge: QuotaExhaustedError on cron mode aborts the iteration" do
    before do
      allow(client).to receive(:fetch_channel).with(channel).and_raise(
        Youtube::QuotaExhaustedError.new("quota busted")
      )
    end

    it "re-raises so Sidekiq retries the cron window" do
      expect {
        described_class.new.perform
      }.to raise_error(Youtube::QuotaExhaustedError)
    end
  end

  describe "edge: NeedsReauthError flips connection and skips" do
    before do
      allow(client).to receive(:fetch_channel).with(channel).and_raise(
        Youtube::NeedsReauthError.new("token revoked")
      )
    end

    it "flips connection.needs_reauth to true and does NOT create a diff" do
      expect {
        described_class.new.perform(channel.id)
      }.not_to change(ChannelDiff, :count)
      expect(connection.reload.needs_reauth).to be(true)
    end
  end

  describe "edge: connection already needs_reauth before the job runs" do
    before do
      connection.update_columns(needs_reauth: true)
    end

    it "skips the channel with a warning, no API call" do
      expect(Youtube::Client).not_to receive(:new)
      expect(Rails.logger).to receive(:warn).with(/needs re-auth/)
      described_class.new.perform(channel.id)
    end
  end

  describe "edge: channel id not found" do
    it "logs and returns without raising" do
      expect(Rails.logger).to receive(:warn).with(/channel not found/)
      expect {
        described_class.new.perform(999_999)
      }.not_to raise_error
    end
  end

  describe "flaw: idempotency on repeat runs with no YouTube changes" do
    before do
      allow(client).to receive(:fetch_channel).with(channel).and_return(diff_payload)
    end

    it "second run does not insert a row or duplicate notification" do
      described_class.new.perform(channel.id)
      expect {
        described_class.new.perform(channel.id)
      }.to change(ChannelDiff, :count).by(0)
        .and change(Notification, :count).by(0)
    end
  end
end
