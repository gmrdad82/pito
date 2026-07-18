# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationWebhookDeliverJob, type: :job do
  let(:notification) { create(:notification, message: "<strong>Hi</strong>") }

  let(:slack_client)   { instance_double(Pito::Notifications::Webhooks::SlackClient) }
  let(:discord_client) { instance_double(Pito::Notifications::Webhooks::DiscordClient) }

  def slack_result(success:, error: nil)
    Pito::Notifications::Webhooks::SlackClient::Result.new(success: success, error: error)
  end

  def discord_result(success:, error: nil)
    Pito::Notifications::Webhooks::DiscordClient::Result.new(success: success, error: error)
  end

  before do
    # Default: nothing configured. Individual examples opt a platform in.
    allow(AppSetting).to receive(:slack_webhook_url).and_return(nil)
    allow(AppSetting).to receive(:discord_webhook_url).and_return(nil)
  end

  def fcm_outcome(ok: false, unregistered: false, disabled: false)
    Pito::Fcm::Sender::Outcome.new(ok: ok, unregistered: unregistered, disabled: disabled)
  end

  def create_device_token(token:)
    DeviceToken.create!(token: token, last_seen_at: Time.current)
  end

  describe "#perform — missing notification" do
    it "is a silent no-op when the row has been deleted" do
      missing_id = notification.id + 99_999
      expect { described_class.new.perform(missing_id) }.not_to raise_error
    end
  end

  describe "#perform — Slack" do
    before do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
    end

    it "delivers a rich, colored Slack attachment (emoji + level color) when configured" do
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: true))

      described_class.new.perform(notification.id)

      expect(Pito::Notifications::Webhooks::SlackClient)
        .to have_received(:new).with("https://hooks.slack.test/abc")
      expect(slack_client).to have_received(:deliver).with({
        "attachments" => [
          { "color" => "#5170ff", "text" => "ℹ️ *Hi*", "mrkdwn_in" => [ "text" ] }
        ]
      })
    end

    it "does not deliver to Slack when the URL is blank" do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("")

      described_class.new.perform(notification.id)

      expect(Pito::Notifications::Webhooks::SlackClient).not_to have_received(:new)
    end

    it "logs and does not raise when the Slack client returns a failure Result" do
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: false, error: "HTTP 500"))

      expect { described_class.new.perform(notification.id) }.not_to raise_error
    end

    it "rescues a raised client error without aborting the job" do
      allow(slack_client).to receive(:deliver).and_raise(StandardError, "boom")

      expect { described_class.new.perform(notification.id) }.not_to raise_error
    end
  end

  describe "#perform — Discord" do
    before do
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
    end

    it "delivers a rich, colored Discord embed (emoji + level color) when configured" do
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: true))

      described_class.new.perform(notification.id)

      expect(Pito::Notifications::Webhooks::DiscordClient)
        .to have_received(:new).with("https://discord.test/webhook")
      expect(discord_client).to have_received(:deliver).with({
        "embeds" => [ { "description" => "ℹ️ **Hi**", "color" => 5337343 } ]
      })
    end

    it "does not deliver to Discord when the URL is blank" do
      allow(AppSetting).to receive(:discord_webhook_url).and_return(nil)

      described_class.new.perform(notification.id)

      expect(Pito::Notifications::Webhooks::DiscordClient).not_to have_received(:new)
    end

    it "rescues a raised client error without aborting the job" do
      allow(discord_client).to receive(:deliver).and_raise(StandardError, "boom")

      expect { described_class.new.perform(notification.id) }.not_to raise_error
    end
  end

  describe "#perform — both platforms" do
    it "delivers to each configured platform independently" do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      # Slack fails; Discord must still be attempted.
      allow(slack_client).to receive(:deliver).and_raise(StandardError, "boom")
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: true))

      described_class.new.perform(notification.id)

      expect(discord_client).to have_received(:deliver).with({
        "embeds" => [ { "description" => "ℹ️ **Hi**", "color" => 5337343 } ]
      })
    end
  end

  describe "#perform — FCM" do
    let(:fcm_sender) { instance_double(Pito::Fcm::Sender) }

    before do
      allow(Pito::Fcm::Sender).to receive(:new).and_return(fcm_sender)
      # Default: every call succeeds. Individual examples override per-token
      # (via a more specific `.with`) or wholesale, as needed.
      allow(fcm_sender).to receive(:call).and_return(fcm_outcome(ok: true))
    end

    it "sends one call per device token with the notification's message and level" do
      first  = create_device_token(token: "token-1")
      second = create_device_token(token: "token-2")

      described_class.new.perform(notification.id)

      expect(fcm_sender).to have_received(:call).with(
        token: first.token, message: notification.message, level: notification.level
      )
      expect(fcm_sender).to have_received(:call).with(
        token: second.token, message: notification.message, level: notification.level
      )
    end

    it "prunes exactly the token whose outcome is unregistered" do
      dead  = create_device_token(token: "dead-token")
      alive = create_device_token(token: "alive-token")
      allow(fcm_sender).to receive(:call)
        .with(hash_including(token: dead.token)).and_return(fcm_outcome(unregistered: true))
      allow(fcm_sender).to receive(:call)
        .with(hash_including(token: alive.token)).and_return(fcm_outcome(ok: true))

      described_class.new.perform(notification.id)

      expect(DeviceToken.exists?(dead.id)).to be(false)
      expect(DeviceToken.exists?(alive.id)).to be(true)
    end

    it "short-circuits the whole token loop on a disabled outcome" do
      create_device_token(token: "token-1")
      create_device_token(token: "token-2")
      create_device_token(token: "token-3")
      allow(fcm_sender).to receive(:call).and_return(fcm_outcome(disabled: true))

      described_class.new.perform(notification.id)

      expect(fcm_sender).to have_received(:call).once
    end

    it "does not prevent later tokens from being attempted after a failed (not unregistered) outcome" do
      first  = create_device_token(token: "flaky-token")
      second = create_device_token(token: "fine-token")
      allow(fcm_sender).to receive(:call)
        .with(hash_including(token: first.token)).and_return(fcm_outcome(ok: false))
      allow(fcm_sender).to receive(:call)
        .with(hash_including(token: second.token)).and_return(fcm_outcome(ok: true))

      described_class.new.perform(notification.id)

      expect(fcm_sender).to have_received(:call).with(hash_including(token: second.token))
    end

    it "never instantiates or calls the Sender when there are no device tokens" do
      described_class.new.perform(notification.id)

      expect(Pito::Fcm::Sender).not_to have_received(:new)
      expect(fcm_sender).not_to have_received(:call)
    end
  end
end
