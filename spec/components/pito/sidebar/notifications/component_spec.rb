# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::Notifications::Component do
  let(:unread_notification) do
    build(:notification, message: "Sync completed", read_at: nil, created_at: 30.minutes.ago)
  end

  let(:read_notification) do
    build(:notification, :read, message: "Weekly digest ready", created_at: 2.days.ago)
  end

  describe "empty state" do
    it "renders 'No notifications' when list is empty" do
      node = render_inline(described_class.new(notifications: []))
      expect(node.to_html).to include("No notifications")
    end

    it "renders no notification rows when empty" do
      node = render_inline(described_class.new(notifications: []))
      expect(node.css(".pito-notification-row")).to be_empty
    end
  end

  describe "notification rows" do
    it "renders a row for each notification" do
      node = render_inline(
        described_class.new(notifications: [ unread_notification, read_notification ])
      )
      expect(node.css(".pito-notification-row").size).to eq(2)
    end

    it "uses .pito-notification-row (not .pito-conversation-row)" do
      node = render_inline(described_class.new(notifications: [ unread_notification ]))
      expect(node.css(".pito-notification-row")).not_to be_empty
      expect(node.css(".pito-conversation-row")).to be_empty
    end

    it "includes the notification message" do
      node = render_inline(described_class.new(notifications: [ unread_notification ]))
      expect(node.to_html).to include("Sync completed")
    end

    it "renders HTML in the message (safe tags survive, not escaped)" do
      html_note = build(:notification, message: "<strong>Done</strong><ul><li>Game A</li></ul>", read_at: nil)
      node = render_inline(described_class.new(notifications: [ html_note ]))
      expect(node.css("strong").map(&:text)).to include("Done")
      expect(node.css("li").map(&:text)).to include("Game A")
      expect(node.to_html).not_to include("&lt;strong&gt;")
    end

    it "strips unsafe tags (no XSS)" do
      evil = build(:notification, message: "<script>alert(1)</script><strong>ok</strong>", read_at: nil)
      node = render_inline(described_class.new(notifications: [ evil ]))
      expect(node.to_html).not_to include("<script>")
      expect(node.css("strong").map(&:text)).to include("ok")
    end
  end

  describe "unread indicator" do
    it "renders the unread dot for unread notifications" do
      node = render_inline(described_class.new(notifications: [ unread_notification ]))
      # Unread: filled dot ●
      expect(node.to_html).to include("●")
    end

    it "renders the read indicator for read notifications" do
      node = render_inline(described_class.new(notifications: [ read_notification ]))
      # Read: empty dot ○
      expect(node.to_html).to include("○")
    end
  end

  describe "keyboard-nav wiring + full message" do
    it "mounts the pito--notifications-nav controller on the list" do
      node = render_inline(described_class.new(notifications: [ unread_notification ]))
      # The wrapper now carries two controllers (nav + the generic list-pager),
      # so match the controller as a word within the attribute, not exactly.
      expect(node.css("[data-controller~='pito--notifications-nav']")).not_to be_empty
    end

    it "also mounts the generic pito--list-pager controller on the same wrapper" do
      node = render_inline(described_class.new(notifications: [ unread_notification ]))
      expect(node.css("[data-controller~='pito--list-pager']")).not_to be_empty
    end

    it "carries data-notification-id and data-read on each row" do
      node = render_inline(described_class.new(notifications: [ read_notification ]))
      row = node.css(".pito-notification-row").first
      expect(row["data-read"]).to eq("true")
      expect(row.key?("data-notification-id")).to be(true)
    end

    it "does not truncate the message (full word-wrapped text)" do
      long = build(:notification, message: "x" * 200, read_at: nil, created_at: 1.minute.ago)
      node = render_inline(described_class.new(notifications: [ long ]))
      msg = node.css(".pito-notification-message").first
      expect(msg).not_to be_nil
      expect(msg["class"]).not_to include("truncate")
      expect(msg.text).to eq("x" * 200)
    end
  end

  describe "CompactTimeAgo timestamps" do
    it "renders a compact relative timestamp for unread notifications" do
      node = render_inline(described_class.new(notifications: [ unread_notification ]))
      # 30 minutes ago → ~30m ago
      expect(node.to_html).to match(/~\d+m ago/)
    end

    it "renders a compact relative timestamp for read notifications" do
      node = render_inline(described_class.new(notifications: [ read_notification ]))
      # 2 days ago → ~2d ago
      expect(node.to_html).to match(/~\d+d ago/)
    end
  end
end
