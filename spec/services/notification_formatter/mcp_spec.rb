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

  # Phase 16 §2 security fix-forward (F2 — 2026-05-10 audit). URL
  # scheme allowlist on `[text](url)` markdown emitted to MCP host
  # renderers. Bad-scheme URLs collapse to bare escaped text.
  describe "F2 — URL scheme allowlist in escape_body_preserving_links" do
    def call(text)
      described_class.escape_body_preserving_links(text)
    end

    it "strips javascript: scheme to bare text" do
      # The markdown regex rejects parens inside the URL, so
      # `javascript:alert(1)` never matches as a markdown link. The
      # exploit shape the allowlist neutralizes is paren-free.
      out = call("see [click me](javascript:alert@1) now")
      expect(out).to include("click me")
      expect(out).not_to include("](javascript")
    end

    it "strips data: scheme to bare text" do
      out = call("[xss](data:text/html,whatever)")
      expect(out).to include("xss")
      expect(out).not_to include("](data")
    end

    it "strips vbscript: scheme to bare text" do
      out = call("[boom](vbscript:msgbox)")
      expect(out).to include("boom")
      expect(out).not_to include("vbscript:")
    end

    it "strips file: scheme to bare text" do
      out = call("[etc](file:///etc/passwd)")
      expect(out).to include("etc")
      expect(out).not_to include("file:")
    end

    it "strips tel: scheme to bare text (not in allowlist)" do
      out = call("[ring](tel:+1234)")
      expect(out).to include("ring")
      expect(out).not_to include("](tel:")
    end

    it "preserves http:// links" do
      out = call("see [docs](http://example.com/d)")
      expect(out).to include("[docs](http://example.com/d)")
    end

    it "preserves https:// links" do
      out = call("see [docs](https://example.com/d)")
      expect(out).to include("[docs](https://example.com/d)")
    end

    it "preserves mailto: links" do
      out = call("contact [owner](mailto:owner@example.com)")
      expect(out).to include("[owner](mailto:owner@example.com)")
    end

    it "preserves leading-slash app paths" do
      out = call("open [video](/videos/42)")
      expect(out).to include("[video](/videos/42)")
    end

    it "strips protocol-relative //evil.com to bare text" do
      out = call("[evil](//evil.com/x)")
      expect(out).to include("evil")
      expect(out).not_to include("](//evil.com")
    end
  end
end
