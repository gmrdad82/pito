require "rails_helper"

RSpec.describe NotificationFormatter::InApp do
  let(:fires_at) { 5.minutes.ago }

  describe "shape" do
    let(:notification) do
      build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "ia-base", fires_at: fires_at,
             event_payload: {
               "video_id" => 1, "video_title" => "demo",
               "channel_title" => "lab", "watch_url" => "https://y/v"
             })
    end

    it "returns the documented hash keys" do
      payload = described_class.payload_for(notification)
      expect(payload.keys).to contain_exactly(
        :title, :body_html, :url, :severity, :severity_class, :glyph,
        :kind, :fires_at_relative, :fires_at_iso, :read
      )
    end

    it "title carries the template's title" do
      expect(described_class.payload_for(notification)[:title])
        .to include("published: demo")
    end

    it "url is the template's url" do
      expect(described_class.payload_for(notification)[:url]).to eq("/videos/1")
    end

    it "kind matches the notification's event_type" do
      expect(described_class.payload_for(notification)[:kind]).to eq("video_published")
    end

    it "glyph is the Q6 emoji for the event_type" do
      expect(described_class.payload_for(notification)[:glyph]).to eq("📺")
    end

    it "fires_at_iso is ISO-8601 UTC" do
      iso = described_class.payload_for(notification)[:fires_at_iso]
      expect(iso).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it "fires_at_relative is a non-empty string" do
      rel = described_class.payload_for(notification)[:fires_at_relative]
      expect(rel).to be_a(String)
      expect(rel).not_to be_empty
    end
  end

  describe "severity_class" do
    it "info → notification-info" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "sev-info", severity: :info)
      expect(described_class.payload_for(n)[:severity_class]).to eq("notification-info")
    end

    it "success → notification-success" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "sev-suc", severity: :success)
      expect(described_class.payload_for(n)[:severity_class]).to eq("notification-success")
    end

    it "warn → notification-warn" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "sev-warn", severity: :warn)
      expect(described_class.payload_for(n)[:severity_class]).to eq("notification-warn")
    end

    it "urgent → notification-urgent" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "sev-urg", severity: :urgent)
      expect(described_class.payload_for(n)[:severity_class]).to eq("notification-urgent")
    end
  end

  describe "severity" do
    it "is the string severity name" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "sev-str", severity: :urgent)
      expect(described_class.payload_for(n)[:severity]).to eq("urgent")
    end
  end

  describe "read flag (in-app is internal — Boolean)" do
    it "is false for unread rows" do
      n = build_stubbed(:notification, :unread, with_calendar_entry: false, dedup_key: "rd-un")
      expect(described_class.payload_for(n)[:read]).to be(false)
    end

    it "is true for read rows" do
      n = build_stubbed(:notification, :read, with_calendar_entry: false, dedup_key: "rd-r1")
      expect(described_class.payload_for(n)[:read]).to be(true)
    end

    it "is a Boolean (NOT a string)" do
      n = build_stubbed(:notification, :read, with_calendar_entry: false, dedup_key: "rd-r2")
      payload = described_class.payload_for(n)
      expect(payload[:read]).to be_in([ true, false ])
      expect(payload[:read]).not_to be_a(String)
    end
  end

  describe "body_html" do
    let(:notification) do
      build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "bh-base",
             event_payload: {
               "video_id" => 1, "video_title" => "demo",
               "channel_title" => "Lab",
               "watch_url" => "https://yt.x/v"
             })
    end

    it "is HTML-safe" do
      expect(described_class.payload_for(notification)[:body_html]).to be_html_safe
    end

    it "converts [text](url) markdown to <a href=...>" do
      html = described_class.payload_for(notification)[:body_html]
      expect(html).to include('<a href="https://yt.x/v">watch on youtube</a>')
    end

    it "strips <script> injected via event_payload" do
      n = build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "bh-xss",
                 event_payload: {
                   "video_id" => 1,
                   "video_title" => "<script>alert(1)</script>",
                   "channel_title" => "Lab"
                 })
      html = described_class.payload_for(n)[:body_html]
      # The `<script>` is escaped to `&lt;script&gt;` before sanitize
      # runs (we do html_escape first), so the sanitizer's strip rule
      # doesn't even see a real <script> tag — but the result is safe
      # either way: no executable <script> survives.
      expect(html).not_to include("<script>")
      expect(html).not_to include("</script>")
    end

    it "html-escapes special chars in user-supplied content" do
      n = build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "bh-qa",
                 event_payload: {
                   "video_id" => 1, "video_title" => "Q&A <live>",
                   "channel_title" => "Lab"
                 })
      html = described_class.payload_for(n)[:body_html]
      expect(html).to include("Q&amp;A &lt;live&gt;")
    end

    it "is empty html-safe string when body is blank" do
      # Sync error template body is non-blank for valid payload; force
      # blank by passing empty event_payload.
      n = build(:notification, :video_published, event_payload: {})
      n.save!
      result = described_class.payload_for(n)[:body_html]
      expect(result).to be_html_safe
    end
  end

  describe "graceful error handling" do
    it "raises ArgumentError for an unknown event_type" do
      n = build(:notification, event_type: "definitely_not_a_real_event")
      n.save!(validate: false)
      expect { described_class.payload_for(n) }
        .to raise_error(ArgumentError, /no template/)
    end
  end

  # Phase 16 §2 security fix-forward (F1 — 2026-05-10 audit). URL
  # scheme allowlist on `[text](url)` markdown rendered into the
  # in-app `body_html`. Bad-scheme URLs collapse to bare text rather
  # than emitting an empty `<a></a>` shell (which Loofah's `href`
  # strip would have left behind).
  describe "F1 — URL scheme allowlist in render_body_html" do
    let(:helper) { described_class }

    def render(body)
      helper.render_body_html(body)
    end

    it "strips javascript: scheme to bare text" do
      # NOTE: the formatter's markdown regex `\[…\]\(…\)` rejects any
      # URL containing `(` / `)`, so `javascript:alert(1)` never
      # matches as a markdown link in the first place — it sits as
      # raw escaped text. The exploit shape the scrubber actually
      # neutralizes is a paren-free payload like
      # `javascript:alert@1` or `javascript:void%200`.
      html = render("see [click me](javascript:alert@1) now")
      expect(html).to include("click me")
      expect(html).not_to match(/href="javascript:/i)
      expect(html).not_to include("<a ")
    end

    it "strips data: scheme to bare text" do
      html = render("[xss](data:text/html,whatever)")
      expect(html).to include("xss")
      expect(html).not_to match(/href="data:/i)
      expect(html).not_to include("<a ")
    end

    it "strips vbscript: scheme to bare text" do
      html = render("[boom](vbscript:msgbox)")
      expect(html).to include("boom")
      expect(html).not_to include("vbscript:")
      expect(html).not_to include("<a ")
    end

    it "strips file: scheme to bare text" do
      html = render("[etc](file:///etc/passwd)")
      expect(html).to include("etc")
      expect(html).not_to include("file:")
      expect(html).not_to include("<a ")
    end

    it "strips tel: scheme to bare text (not in allowlist)" do
      html = render("[ring](tel:+1234)")
      expect(html).to include("ring")
      expect(html).not_to include("<a ")
    end

    it "preserves http:// links" do
      html = render("see [docs](http://example.com/d)")
      expect(html).to include(%(<a href="http://example.com/d">docs</a>))
    end

    it "preserves https:// links" do
      html = render("see [docs](https://example.com/d)")
      expect(html).to include(%(<a href="https://example.com/d">docs</a>))
    end

    it "preserves mailto: links" do
      html = render("contact [owner](mailto:owner@example.com)")
      expect(html).to include(%(<a href="mailto:owner@example.com">owner</a>))
    end

    it "preserves leading-slash app paths" do
      html = render("open [video](/videos/42)")
      expect(html).to include(%(<a href="/videos/42">video</a>))
    end

    it "strips an empty href to bare text" do
      html = render("see [empty]()")
      # The empty-URL link can't even match the regex (which requires
      # at least one non-paren non-space char inside the parentheses),
      # so the raw markdown passes through escaped — and the
      # critical assertion is that no `<a>` tag with an empty href
      # survives.
      expect(html).not_to include(%(<a href="">))
      expect(html).not_to include(%(<a href=""></a>))
    end

    it "strips protocol-relative //evil.com to bare text" do
      # Per `url_scheme_allowed?`, a leading `/` followed by another
      # `/` (protocol-relative) is rejected (no scheme parsed) — the
      # check `start_with?("/") && !start_with?("//")` short-circuits.
      html = render("[evil](//evil.com/x)")
      expect(html).to include("evil")
      expect(html).not_to include("<a ")
    end

    it "does not leave a dangling <a></a> shell when scheme is rejected" do
      html = render("[x](javascript:1)")
      expect(html).not_to include("<a")
      expect(html).not_to include("</a>")
    end
  end
end
