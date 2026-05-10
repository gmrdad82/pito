require "rails_helper"

RSpec.describe NotificationFormatter::Mcp do
  let(:fires_at) { Time.utc(2026, 5, 10, 12, 0, 0) }
  let(:notification) do
    create(:notification, :video_published, fires_at: fires_at,
           event_payload: {
             "video_id" => 42, "video_title" => "demo",
             "channel_title" => "Lab", "watch_url" => "https://yt.x/v"
           })
  end

  describe "shape" do
    it "returns exactly the documented keys, no extras" do
      payload = described_class.payload_for(notification)
      expect(payload.keys).to contain_exactly(
        :id, :title, :body_md, :url, :severity, :kind, :fires_at_iso, :read
      )
    end

    it "id is the notification UUID/id as a string" do
      payload = described_class.payload_for(notification)
      expect(payload[:id]).to eq(notification.id.to_s)
      expect(payload[:id]).to be_a(String)
    end

    it "kind is the event_type string" do
      expect(described_class.payload_for(notification)[:kind])
        .to eq("video_published")
    end

    it "severity is the string severity name" do
      expect(described_class.payload_for(notification)[:severity])
        .to eq("info")
    end

    it "fires_at_iso is ISO-8601 UTC" do
      expect(described_class.payload_for(notification)[:fires_at_iso])
        .to eq("2026-05-10T12:00:00Z")
    end

    it "url is the template's url (leading-slash path)" do
      expect(described_class.payload_for(notification)[:url]).to eq("/videos/42")
    end

    it "title is the template's title" do
      expect(described_class.payload_for(notification)[:title])
        .to eq("published: demo")
    end
  end

  describe "body_md" do
    it "carries [text](url) markdown links" do
      expect(described_class.payload_for(notification)[:body_md])
        .to include("[watch on youtube](https://yt.x/v)")
    end

    it "backslash-escapes the same set as Discord" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 1, "video_title" => "video *bold*",
                   "channel_title" => "lab"
                 })
      expect(described_class.payload_for(n)[:body_md]).to include("\\*bold\\*")
    end
  end

  describe "read (yes/no per CLAUDE.md boundary rule)" do
    it "is `\"no\"` for unread" do
      n = create(:notification, :video_published, :unread)
      expect(described_class.payload_for(n)[:read]).to eq("no")
    end

    it "is `\"yes\"` for read" do
      n = create(:notification, :video_published, :read)
      expect(described_class.payload_for(n)[:read]).to eq("yes")
    end

    it "is a String (NEVER a Boolean) at the boundary" do
      n = create(:notification, :video_published, :read)
      val = described_class.payload_for(n)[:read]
      expect(val).to be_a(String)
      expect(val).not_to be_in([ true, false ])
    end
  end

  describe "smuggle attempts" do
    it "backslash-escapes <script> injected via event_payload" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 1,
                   "video_title" => "<script>alert(1)</script>",
                   "channel_title" => "lab"
                 })
      payload = described_class.payload_for(n)
      # The `<` `>` chars are in the MCP escape set (mirrors Discord
      # per Q11). They are backslash-escaped so the markdown does not
      # render as raw HTML in MCP-host UIs.
      expect(payload[:body_md]).to include("\\<script\\>")
      expect(payload[:body_md]).to include("\\</script\\>")
      expect(payload[:body_md]).not_to include("<script>")
    end
  end

  describe "unknown event_type" do
    it "raises ArgumentError" do
      n = build(:notification, event_type: "definitely_not_a_real_event")
      n.save!(validate: false)
      expect { described_class.payload_for(n) }
        .to raise_error(ArgumentError, /no template/)
    end
  end
end
