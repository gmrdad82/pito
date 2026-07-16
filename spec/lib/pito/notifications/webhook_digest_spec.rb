# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::WebhookDigest do
  let(:slack_client)   { instance_double(Pito::Notifications::Webhooks::SlackClient) }
  let(:discord_client) { instance_double(Pito::Notifications::Webhooks::DiscordClient) }

  def slack_result(success:, error: nil)
    Pito::Notifications::Webhooks::SlackClient::Result.new(success: success, error: error)
  end

  def discord_result(success:, error: nil)
    Pito::Notifications::Webhooks::DiscordClient::Result.new(success: success, error: error)
  end

  let(:table_rows) { [ [ "Alpha", "2026-08-01" ], [ "Bee", "2026-08-15" ] ] }

  # Built independently from `table_rows` with plain Ruby (never calling the
  # private `WebhookDigest.table`) so it exercises the real expected shape:
  # col1 left-justified to the widest value, then " │ ", then col2, one line
  # per row, inside a fenced code block.
  let(:expected_table) do
    width = table_rows.map { |col1, _| col1.length }.max
    lines = table_rows.map { |col1, col2| "#{col1.ljust(width)} │ #{col2}" }
    "```\n#{lines.join("\n")}\n```"
  end

  before do
    # Default: nothing configured. Individual examples opt a platform in.
    allow(AppSetting).to receive(:slack_webhook_url).and_return(nil)
    allow(AppSetting).to receive(:discord_webhook_url).and_return(nil)
  end

  describe ".call — accent colors" do
    before do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: true))
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: true))
    end

    it "uses #5170ff / 0x5170ff for the RELEASES accent" do
      described_class.call(title: "🎮 Upcoming releases", accent: described_class::RELEASES, rows: table_rows)

      expect(slack_client).to have_received(:deliver) do |payload|
        expect(payload["attachments"].first["color"]).to eq("#5170ff")
      end
      expect(discord_client).to have_received(:deliver) do |payload|
        expect(payload["embeds"].first["color"]).to eq(0x5170ff)
      end
    end

    it "uses #f59e0b / 0xf59e0b for the ACHIEVEMENTS accent" do
      described_class.call(title: "🏆 New achievements", accent: described_class::ACHIEVEMENTS, rows: table_rows)

      expect(slack_client).to have_received(:deliver) do |payload|
        expect(payload["attachments"].first["color"]).to eq("#f59e0b")
      end
      expect(discord_client).to have_received(:deliver) do |payload|
        expect(payload["embeds"].first["color"]).to eq(0xf59e0b)
      end
    end
  end

  describe ".call — table body" do
    before do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: true))
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: true))
    end

    it "sends a single colored Slack attachment with the title and aligned table in its text" do
      described_class.call(title: "🎮 Upcoming releases", accent: described_class::RELEASES, rows: table_rows)

      expect(Pito::Notifications::Webhooks::SlackClient).to have_received(:new).with("https://hooks.slack.test/abc")
      expect(slack_client).to have_received(:deliver).with({
        "attachments" => [
          {
            "color"     => "#5170ff",
            "text"      => "🎮 Upcoming releases\n#{expected_table}",
            "mrkdwn_in" => [ "text" ]
          }
        ]
      })
    end

    it "sends a single colored Discord embed with the title and aligned table as its description" do
      described_class.call(title: "🎮 Upcoming releases", accent: described_class::RELEASES, rows: table_rows)

      expect(Pito::Notifications::Webhooks::DiscordClient).to have_received(:new).with("https://discord.test/webhook")
      expect(discord_client).to have_received(:deliver).with({
        "embeds" => [
          {
            "title"       => "🎮 Upcoming releases",
            "description" => expected_table,
            "color"       => 0x5170ff
          }
        ]
      })
    end
  end

  describe ".call — empty rows" do
    before do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new)
    end

    it "is a no-op when rows is an empty array" do
      described_class.call(title: "Title", accent: described_class::RELEASES, rows: [])

      expect(Pito::Notifications::Webhooks::SlackClient).not_to have_received(:new)
      expect(Pito::Notifications::Webhooks::DiscordClient).not_to have_received(:new)
    end

    it "is a no-op when rows is nil" do
      described_class.call(title: "Title", accent: described_class::RELEASES, rows: nil)

      expect(Pito::Notifications::Webhooks::SlackClient).not_to have_received(:new)
      expect(Pito::Notifications::Webhooks::DiscordClient).not_to have_received(:new)
    end
  end

  describe ".call — missing webhook URLs" do
    it "does not contact Slack when the Slack webhook URL is blank" do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: true))

      described_class.call(title: "Title", accent: described_class::RELEASES, rows: table_rows)

      expect(Pito::Notifications::Webhooks::SlackClient).not_to have_received(:new)
      expect(discord_client).to have_received(:deliver)
    end

    it "does not contact Discord when the Discord webhook URL is blank" do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return(nil)
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new)
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: true))

      described_class.call(title: "Title", accent: described_class::RELEASES, rows: table_rows)

      expect(slack_client).to have_received(:deliver)
      expect(Pito::Notifications::Webhooks::DiscordClient).not_to have_received(:new)
    end
  end

  describe ".call — best-effort delivery" do
    it "does not raise when the Slack client raises, and still attempts Discord" do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      allow(slack_client).to receive(:deliver).and_raise(StandardError, "boom")
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: true))

      expect do
        described_class.call(title: "Title", accent: described_class::RELEASES, rows: table_rows)
      end.not_to raise_error

      expect(discord_client).to have_received(:deliver)
    end

    it "does not raise when the Discord client raises, and Slack was still attempted" do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: true))
      allow(discord_client).to receive(:deliver).and_raise(StandardError, "boom")

      expect do
        described_class.call(title: "Title", accent: described_class::RELEASES, rows: table_rows)
      end.not_to raise_error

      expect(slack_client).to have_received(:deliver)
    end

    it "does not raise when a client returns a failure Result" do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: false, error: "HTTP 500"))
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: false, error: "HTTP 500"))

      expect do
        described_class.call(title: "Title", accent: described_class::RELEASES, rows: table_rows)
      end.not_to raise_error
    end
  end

  describe ".deliver" do
    it "delegates to .call with the same title/accent/rows" do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: true))

      described_class.deliver(title: "Title", accent: described_class::RELEASES, rows: table_rows)

      expect(slack_client).to have_received(:deliver)
    end
  end
end
