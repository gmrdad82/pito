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
end
