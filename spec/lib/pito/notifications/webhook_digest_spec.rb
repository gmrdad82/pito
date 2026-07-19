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

  # Built independently from `table_rows` too: "<count>: <comma-joined col1
  # values>" — the previewed-surface line (Discord embed description / Slack
  # attachment text), which the shade renders verbatim so it must stay
  # fence-free.
  let(:expected_summary) do
    "#{table_rows.size}: #{table_rows.map(&:first).join(", ")}"
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

    it "sends a single colored Slack attachment whose text is the title + a clean summary line (no fence), and whose fields carry the aligned table" do
      described_class.call(title: "🎮 Upcoming releases", accent: described_class::RELEASES, rows: table_rows)

      expect(Pito::Notifications::Webhooks::SlackClient).to have_received(:new).with("https://hooks.slack.test/abc")
      expect(slack_client).to have_received(:deliver).with({
        "attachments" => [
          {
            "color"     => "#5170ff",
            "text"      => "🎮 Upcoming releases\n#{expected_summary}",
            "fields"    => [
              {
                "title" => "Details",
                "value" => expected_table,
                "short" => false
              }
            ],
            "mrkdwn_in" => [ "text", "fields" ]
          }
        ]
      })
    end

    it "sends a single colored Discord embed whose description is a clean summary line (no fence), and whose fields carry the aligned table" do
      described_class.call(title: "🎮 Upcoming releases", accent: described_class::RELEASES, rows: table_rows)

      expect(Pito::Notifications::Webhooks::DiscordClient).to have_received(:new).with("https://discord.test/webhook")
      expect(discord_client).to have_received(:deliver).with({
        "embeds" => [
          {
            "title"       => "🎮 Upcoming releases",
            "description" => expected_summary,
            "color"       => 0x5170ff,
            "fields"      => [
              {
                "name"  => "Details",
                "value" => expected_table
              }
            ]
          }
        ]
      })
    end

    # Regression: the Android shade (and Slack mobile) preview the Discord
    # embed description / Slack attachment text VERBATIM — a fenced code
    # block used to leak through as raw "```" noise. Neither previewed
    # surface may ever carry a backtick again.
    it "never puts a backtick in the previewed surface (Discord description / Slack attachment text)" do
      described_class.call(title: "🎮 Upcoming releases", accent: described_class::RELEASES, rows: table_rows)

      expect(slack_client).to have_received(:deliver) do |payload|
        expect(payload["attachments"].first["text"]).not_to include("`")
      end
      expect(discord_client).to have_received(:deliver) do |payload|
        expect(payload["embeds"].first["description"]).not_to include("`")
      end
    end
  end

  describe ".call — summary list cap" do
    # 7 rows > SUMMARY_LIST_LIMIT (5) so the preview line must collapse the
    # tail into "+N more" instead of listing every row.
    let(:many_rows) { (1..7).map { |n| [ "Row #{n}", "Value #{n}" ] } }

    before do
      allow(AppSetting).to receive(:slack_webhook_url).and_return("https://hooks.slack.test/abc")
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(Pito::Notifications::Webhooks::SlackClient).to receive(:new).and_return(slack_client)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      allow(slack_client).to receive(:deliver).and_return(slack_result(success: true))
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: true))
    end

    it "caps the Discord description's list at SUMMARY_LIST_LIMIT entries plus a '+N more' tail" do
      described_class.call(title: "Title", accent: described_class::RELEASES, rows: many_rows)

      expect(discord_client).to have_received(:deliver) do |payload|
        expect(payload["embeds"].first["description"])
          .to eq("7: Row 1, Row 2, Row 3, Row 4, Row 5, +2 more")
      end
    end

    it "caps the Slack text's list at SUMMARY_LIST_LIMIT entries plus a '+N more' tail" do
      described_class.call(title: "Title", accent: described_class::RELEASES, rows: many_rows)

      expect(slack_client).to have_received(:deliver) do |payload|
        expect(payload["attachments"].first["text"])
          .to eq("Title\n7: Row 1, Row 2, Row 3, Row 4, Row 5, +2 more")
      end
    end

    it "still lists every row in the Discord field's full table, uncapped" do
      described_class.call(title: "Title", accent: described_class::RELEASES, rows: many_rows)

      expect(discord_client).to have_received(:deliver) do |payload|
        value = payload["embeds"].first["fields"].first["value"]
        many_rows.each { |col1, col2| expect(value).to include("#{col1} │ #{col2}") }
      end
    end
  end

  describe ".call — Discord field value truncation (DISCORD_FIELD_VALUE_LIMIT)" do
    # 40 rows of ~34 chars each comfortably busts the 1024-char field-value
    # cap, forcing truncate_table to drop trailing rows.
    let(:huge_rows) { (1..40).map { |n| [ "Achievement number #{n}", "Channel #{n}" ] } }

    before do
      allow(AppSetting).to receive(:discord_webhook_url).and_return("https://discord.test/webhook")
      allow(AppSetting).to receive(:slack_webhook_url).and_return(nil)
      allow(Pito::Notifications::Webhooks::DiscordClient).to receive(:new).and_return(discord_client)
      allow(discord_client).to receive(:deliver).and_return(discord_result(success: true))
    end

    it "keeps the Discord field value at or under the 1024-char limit" do
      described_class.call(title: "Title", accent: described_class::ACHIEVEMENTS, rows: huge_rows)

      expect(discord_client).to have_received(:deliver) do |payload|
        value = payload["embeds"].first["fields"].first["value"]
        expect(value.length).to be <= described_class::DISCORD_FIELD_VALUE_LIMIT
      end
    end

    it "ends the truncated field value with a '+N more' line inside the fence" do
      described_class.call(title: "Title", accent: described_class::ACHIEVEMENTS, rows: huge_rows)

      expect(discord_client).to have_received(:deliver) do |payload|
        value = payload["embeds"].first["fields"].first["value"]
        expect(value).to start_with("```\n")
        expect(value).to match(/\+\d+ more\n```\z/)
      end
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
