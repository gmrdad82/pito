# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::WebhookFormatter do
  describe ".slack" do
    it "converts <strong> to Slack bold markers" do
      expect(described_class.slack("<strong>Synced</strong>")).to eq("*Synced*")
    end

    it "converts <b> to Slack bold markers" do
      expect(described_class.slack("<b>Done</b>")).to eq("*Done*")
    end

    it "renders <li> items as • bullets on their own lines" do
      html = "<ul><li>Alpha</li><li>Beta</li></ul>"
      expect(described_class.slack(html)).to eq("• Alpha\n• Beta")
    end

    it "turns <br> into newlines" do
      expect(described_class.slack("a<br>b")).to eq("a\nb")
    end

    it "breaks lines on block-element boundaries" do
      expect(described_class.slack("<div>one</div><div>two</div>")).to eq("one\n\ntwo")
    end

    it "decodes HTML entities" do
      expect(described_class.slack("Tom &amp; Jerry &lt;3")).to eq("Tom & Jerry <3")
    end

    it "combines a heading with a bulleted list" do
      html = "<strong>Imported 2 videos</strong><ul><li>First</li><li>Second</li></ul>"
      expect(described_class.slack(html)).to eq("*Imported 2 videos*\n• First\n• Second")
    end

    it "passes plain text through unchanged" do
      expect(described_class.slack("Nothing fancy here")).to eq("Nothing fancy here")
    end

    it "collapses excess blank lines" do
      expect(described_class.slack("a<br><br><br><br>b")).to eq("a\n\nb")
    end
  end

  describe ".discord" do
    it "converts <strong> to Discord bold markers" do
      expect(described_class.discord("<strong>Synced</strong>")).to eq("**Synced**")
    end

    it "renders <li> items as - bullets on their own lines" do
      html = "<ul><li>Alpha</li><li>Beta</li></ul>"
      expect(described_class.discord(html)).to eq("- Alpha\n- Beta")
    end

    it "decodes HTML entities" do
      expect(described_class.discord("Tom &amp; Jerry")).to eq("Tom & Jerry")
    end

    it "combines a heading with a bulleted list" do
      html = "<strong>Imported</strong><ul><li>First</li></ul>"
      expect(described_class.discord(html)).to eq("**Imported**\n- First")
    end

    it "passes plain text through unchanged" do
      expect(described_class.discord("Nothing fancy here")).to eq("Nothing fancy here")
    end
  end

  describe "robustness" do
    it "does not raise on malformed / unclosed HTML" do
      malformed = "<strong>unclosed <li>item & <broken"
      expect { described_class.slack(malformed) }.not_to raise_error
      expect { described_class.discord(malformed) }.not_to raise_error
    end

    it "does not raise on a nil message" do
      expect { described_class.slack(nil) }.not_to raise_error
      expect(described_class.slack(nil)).to eq("")
    end
  end

  describe ".slack_payload" do
    it "previews the plain title, and puts the mrkdwn body in a details field" do
      notification = build(:notification, title: "Vids synced", message: "<strong>Done</strong>", level: "success")
      payload      = described_class.slack_payload(notification)

      attachment = payload["attachments"].first
      expect(attachment["color"]).to eq("good")
      expect(attachment["text"]).to eq("✅ Vids synced")
      expect(attachment["fields"]).to eq([ { "title" => "Details", "value" => "*Done*", "short" => false } ])
      expect(attachment["mrkdwn_in"]).to eq([ "text", "fields" ])
    end

    it "defaults to the info color/emoji for a plain notification" do
      attachment = described_class.slack_payload(build(:notification, title: "Note", message: "Hi"))["attachments"].first
      expect(attachment["color"]).to eq("#5170ff")
      expect(attachment["text"]).to start_with("ℹ️")
    end

    # Regression: a phone's notification shade renders the attachment `text`
    # VERBATIM — a bold `<strong>` summary used to preview as literal
    # "**...**" instead of bold. The previewed surface may never carry a
    # markdown marker again; the mrkdwn body still reaches the details field.
    it "never puts a markdown bold marker in the previewed surface" do
      notification = build(:notification, title: "Vids synced", message: "<strong>@gmrdad82: 1 updated</strong>")
      text = described_class.slack_payload(notification)["attachments"].first["text"]

      expect(text).not_to include("*")
    end

    it "falls back to previewing the plain (tag-stripped) message, with no details field, when the notification has no title" do
      notification = build(:notification, message: "<strong>Done</strong>", level: "success")
      attachment   = described_class.slack_payload(notification)["attachments"].first

      expect(attachment["text"]).to eq("✅ Done")
      expect(attachment["fields"]).to eq([])
    end
  end

  describe ".discord_payload" do
    it "previews the plain title, and puts the markdown body in a details field" do
      notification = build(:notification, title: "Update rejected", message: "<strong>Oops</strong>", level: "error")
      payload      = described_class.discord_payload(notification)

      embed = payload["embeds"].first
      expect(embed["color"]).to eq(0xe74c3c)
      expect(embed["description"]).to eq("🛑 Update rejected")
      expect(embed["fields"]).to eq([ { "name" => "Details", "value" => "**Oops**" } ])
    end

    it "defaults to the info color/emoji for a plain notification" do
      embed = described_class.discord_payload(build(:notification, title: "Note", message: "Hi"))["embeds"].first
      expect(embed["color"]).to eq(0x5170ff)
      expect(embed["description"]).to start_with("ℹ️")
    end

    # Regression: same lockscreen-verbatim rendering as Slack — see the
    # matching Slack regression test above.
    it "never puts a markdown bold marker in the previewed surface" do
      notification = build(:notification, title: "Vids synced", message: "<strong>@gmrdad82: 1 updated</strong>")
      description = described_class.discord_payload(notification)["embeds"].first["description"]

      expect(description).not_to include("*")
    end

    it "falls back to previewing the plain (tag-stripped) message, with no details field, when the notification has no title" do
      notification = build(:notification, message: "<strong>Oops</strong>", level: "error")
      embed        = described_class.discord_payload(notification)["embeds"].first

      expect(embed["description"]).to eq("🛑 Oops")
      expect(embed["fields"]).to eq([])
    end
  end
end
