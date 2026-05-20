require "rails_helper"

# Phase 26 — 01e. Per-user digest delivery job.
RSpec.describe DailyDigestDeliverJob, type: :job do
  let(:user) { create(:user, time_zone: "Europe/Bucharest") }
  let(:slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:discord_url) { "https://discord.com/api/webhooks/123456789012345678/abcDEF_xyz-789" }

  def stub_slack(status: 200, body: "ok")
    stub_request(:post, slack_url).to_return(status: status, body: body)
  end

  def stub_discord(status: 204, body: "")
    stub_request(:post, discord_url).to_return(status: status, body: body)
  end

  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The "daily digest is on" gate is
  # the shared `AppSetting.notifications_send_daily_digest?` flag AND
  # the existence of a `NotificationDeliveryChannel` row with a present
  # webhook URL. The per-brand `daily_digest` column was dropped.
  let!(:slack_channel) do
    NotificationDeliveryChannel.create!(kind: "slack", webhook_url: slack_url)
  end

  before do
    AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
  end

  describe "happy path" do
    it "delivers to a single enabled Slack channel" do
      stub = stub_slack
      described_class.new.perform(user.id)
      expect(stub).to have_been_requested
    end

    it "delivers to both Slack and Discord when both are enabled" do
      discord_channel = NotificationDeliveryChannel.create!(
        kind: "discord", webhook_url: discord_url
      )
      stub_s = stub_slack
      stub_d = stub_discord
      described_class.new.perform(user.id)
      expect(stub_s).to have_been_requested
      expect(stub_d).to have_been_requested
      _ = discord_channel
    end

    it "treats a 204 from Discord as success" do
      slack_channel.destroy!
      NotificationDeliveryChannel.create!(kind: "discord", webhook_url: discord_url)
      stub_discord(status: 204)
      expect {
        described_class.new.perform(user.id)
      }.not_to raise_error
    end
  end

  describe "no-op paths" do
    it "no-ops when the user has been deleted between enqueue and run" do
      expect {
        described_class.new.perform(0)
      }.not_to raise_error
    end

    it "no-ops when the shared daily-digest toggle is off" do
      AppSetting.set_notification_toggle!(:notifications_send_daily_digest, false)
      expect {
        described_class.new.perform(user.id)
      }.not_to raise_error
    end
  end

  describe "transient failures" do
    it "raises TransientFailure on Slack HTTP 429" do
      stub_slack(status: 429, body: "rate limited")
      expect {
        described_class.new.perform(user.id)
      }.to raise_error(DailyDigestDeliverJob::TransientFailure)
    end

    it "raises TransientFailure on Slack HTTP 500" do
      stub_slack(status: 500, body: "boom")
      expect {
        described_class.new.perform(user.id)
      }.to raise_error(DailyDigestDeliverJob::TransientFailure)
    end

    it "raises TransientFailure on network timeout" do
      stub_request(:post, slack_url).to_raise(::Net::OpenTimeout.new("connect"))
      expect {
        described_class.new.perform(user.id)
      }.to raise_error(DailyDigestDeliverJob::TransientFailure)
    end

    it "does NOT create a notification row on transient failure" do
      stub_slack(status: 500)
      expect {
        begin
          described_class.new.perform(user.id)
        rescue DailyDigestDeliverJob::TransientFailure
          # expected
        end
      }.not_to change { Notification.where(event_type: "digest_delivery_failed").count }
    end
  end

  describe "permanent failures" do
    it "does NOT raise on Slack HTTP 404" do
      stub_slack(status: 404, body: "")
      expect {
        described_class.new.perform(user.id)
      }.not_to raise_error
    end

    it "does NOT raise on Slack HTTP 401" do
      stub_slack(status: 401, body: "unauthorized")
      expect {
        described_class.new.perform(user.id)
      }.not_to raise_error
    end

    it "does NOT raise on Slack HTTP 400" do
      stub_slack(status: 400, body: "bad payload")
      expect {
        described_class.new.perform(user.id)
      }.not_to raise_error
    end

    it "creates a notification row tagged `digest_delivery_failed`" do
      stub_slack(status: 404)
      expect {
        described_class.new.perform(user.id)
      }.to change { Notification.where(event_type: "digest_delivery_failed").count }.by(1)
    end

    it "records the failing channel id and HTTP status in the notification body" do
      stub_slack(status: 404, body: "channel missing")
      described_class.new.perform(user.id)
      n = Notification.where(event_type: "digest_delivery_failed").last
      expect(n.body).to include("channel##{slack_channel.id}")
      expect(n.body).to include("404")
    end
  end

  describe "mixed outcomes (Slack permanent, Discord success)" do
    before do
      NotificationDeliveryChannel.create!(kind: "discord", webhook_url: discord_url)
    end

    it "Discord succeeds even if Slack permanently fails" do
      slack_stub = stub_slack(status: 404)
      discord_stub = stub_discord(status: 204)
      expect {
        described_class.new.perform(user.id)
      }.not_to raise_error
      expect(slack_stub).to have_been_requested
      expect(discord_stub).to have_been_requested
    end

    it "raises TransientFailure when Discord transient-fails even if Slack succeeded" do
      stub_slack(status: 200)
      stub_discord(status: 503)
      expect {
        described_class.new.perform(user.id)
      }.to raise_error(DailyDigestDeliverJob::TransientFailure)
    end
  end

  describe "all-quiet user" do
    it "still delivers when there is zero activity in the last 24h" do
      stub = stub_slack
      described_class.new.perform(user.id)
      expect(stub).to have_been_requested
      body = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.first.body
      expect(body).to include("no activity")
    end
  end

  describe "retry posture" do
    it "exposes a backoff ladder of 1m, 5m, 15m" do
      expect(described_class::RETRY_BACKOFF_SECONDS).to eq([ 60, 5 * 60, 15 * 60 ])
    end

    it "registers `retry_on TransientFailure` (ActiveJob)" do
      # `retry_on` registers an entry in `rescue_handlers`. The handler
      # is keyed by the exception's stringified name; for ActiveJob 7+
      # the registry lives on the class's `rescue_handlers` array.
      handlers = described_class.rescue_handlers.map(&:first)
      expect(handlers).to include("DailyDigestDeliverJob::TransientFailure")
    end
  end
end
