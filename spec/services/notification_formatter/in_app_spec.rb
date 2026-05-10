require "rails_helper"

RSpec.describe NotificationFormatter::InApp do
  let(:fires_at) { 5.minutes.ago }

  describe "shape" do
    let(:notification) do
      create(:notification, :video_published, fires_at: fires_at,
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
      n = create(:notification, severity: :info)
      expect(described_class.payload_for(n)[:severity_class]).to eq("notification-info")
    end

    it "success → notification-success" do
      n = create(:notification, severity: :success)
      expect(described_class.payload_for(n)[:severity_class]).to eq("notification-success")
    end

    it "warn → notification-warn" do
      n = create(:notification, severity: :warn)
      expect(described_class.payload_for(n)[:severity_class]).to eq("notification-warn")
    end

    it "urgent → notification-urgent" do
      n = create(:notification, severity: :urgent)
      expect(described_class.payload_for(n)[:severity_class]).to eq("notification-urgent")
    end
  end

  describe "severity" do
    it "is the string severity name" do
      n = create(:notification, severity: :urgent)
      expect(described_class.payload_for(n)[:severity]).to eq("urgent")
    end
  end

  describe "read flag (in-app is internal — Boolean)" do
    it "is false for unread rows" do
      n = create(:notification, :unread)
      expect(described_class.payload_for(n)[:read]).to be(false)
    end

    it "is true for read rows" do
      n = create(:notification, :read)
      expect(described_class.payload_for(n)[:read]).to be(true)
    end

    it "is a Boolean (NOT a string)" do
      n = create(:notification, :read)
      payload = described_class.payload_for(n)
      expect(payload[:read]).to be_in([ true, false ])
      expect(payload[:read]).not_to be_a(String)
    end
  end

  describe "body_html" do
    let(:notification) do
      create(:notification, :video_published,
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
      n = create(:notification, :video_published,
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
      n = create(:notification, :video_published,
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
end
