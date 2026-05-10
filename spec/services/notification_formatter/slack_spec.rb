require "rails_helper"

RSpec.describe NotificationFormatter::Slack do
  before do
    allow(Rails.application.credentials).to receive(:dig).and_return(nil)
    allow(Rails.application.routes).to receive(:default_url_options)
      .and_return(host: "app.pitomd.com", protocol: "https")
  end

  let(:fires_at) { Time.utc(2026, 5, 10, 12, 0, 0) }

  describe "per-kind dispatch" do
    %i[
      video_published
      video_pre_publish_check_missed
      game_release_upcoming
      game_release_today
      milestone_reached
      calendar_entry_firing
      sync_error
      youtube_reauth_needed
    ].each do |kind|
      it "produces a valid Slack payload for #{kind}" do
        n = build_notification_for_kind(kind, fires_at)
        payload = described_class.payload_for(n)

        expect(payload[:username]).to eq("pito")
        expect(payload).not_to have_key(:icon_url)
        expect(payload[:blocks]).to be_an(Array).and have_attributes(length: 3)

        header, section, context = payload[:blocks]
        expect(header[:type]).to eq("header")
        expect(header[:text][:type]).to eq("plain_text")
        expect(header[:text][:text]).to be_a(String)
        expect(header[:text][:emoji]).to be(true)

        expect(section[:type]).to eq("section")
        expect(section[:text][:type]).to eq("mrkdwn")
        expect(section[:text][:text]).to be_a(String)

        expect(context[:type]).to eq("context")
        expect(context[:elements].first[:type]).to eq("mrkdwn")
        expect(context[:elements].first[:text]).to include(n.event_type.to_s)
        expect(context[:elements].first[:text]).to include("2026-05-10T12:00:00Z")
      end
    end
  end

  describe "header" do
    it "carries `<emoji> <title>`" do
      n = build_notification_for_kind(:video_published, fires_at)
      header_text = described_class.payload_for(n)[:blocks][0][:text][:text]
      expect(header_text).to start_with("📺 ")
    end

    it "is truncated to 150 chars" do
      n = create(:notification, :video_published,
                 event_payload: { "video_title" => "x" * 300, "video_id" => 1 })
      header_text = described_class.payload_for(n)[:blocks][0][:text][:text]
      expect(header_text.length).to be <= 150
      expect(header_text).to end_with("…")
    end
  end

  describe "section" do
    it "is mrkdwn type" do
      n = build_notification_for_kind(:video_published, fires_at)
      expect(described_class.payload_for(n)[:blocks][1][:text][:type]).to eq("mrkdwn")
    end

    it "is truncated to 3000 chars" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 1, "video_title" => "x" * 5000,
                   "channel_title" => "c"
                 })
      section_text = described_class.payload_for(n)[:blocks][1][:text][:text]
      expect(section_text.length).to be <= 3000
      expect(section_text).to end_with("…")
    end

    it "appends `<url|view in pito>` when notification has a URL" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 42, "video_title" => "demo",
                   "channel_title" => "lab", "watch_url" => "https://yt.x/v"
                 })
      section_text = described_class.payload_for(n)[:blocks][1][:text][:text]
      expect(section_text).to end_with("<https://app.pitomd.com/videos/42|view in pito>")
    end

    it "does NOT append the view link when URL is nil" do
      # Build a row with `event_type: "calendar_entry_firing"` but with
      # neither entry_id in event_payload nor source_calendar_entry, so
      # url comes back nil.
      n = build(:notification, :calendar_entry_firing,
                event_payload: { "title" => "x", "description" => "y" },
                with_calendar_entry: false,
                dedup_key: "no-url")
      n.save!
      section_text = described_class.payload_for(n)[:blocks][1][:text][:text]
      expect(section_text).not_to include("view in pito")
    end

    it "rewrites markdown [text](url) into Slack <url|text>" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 1, "video_title" => "demo",
                   "channel_title" => "lab", "watch_url" => "https://yt.x/v"
                 })
      section_text = described_class.payload_for(n)[:blocks][1][:text][:text]
      expect(section_text).to include("<https://yt.x/v|watch on youtube>")
    end
  end

  describe "escaping (Slack mrkdwn)" do
    it "html-encodes < and > in body" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 1, "video_title" => "<script>x</script>",
                   "channel_title" => "lab"
                 })
      section_text = described_class.payload_for(n)[:blocks][1][:text][:text]
      expect(section_text).to include("&lt;script&gt;")
      expect(section_text).not_to include("<script>")
    end

    it "html-encodes & in body" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 1, "video_title" => "Q&A live",
                   "channel_title" => "lab"
                 })
      section_text = described_class.payload_for(n)[:blocks][1][:text][:text]
      expect(section_text).to include("Q&amp;A live")
    end

    it "does NOT double-escape Slack-meaningful chars (`*`)" do
      # Slack's own mrkdwn handles `*` for bold. Per spec test: a
      # notification with `event_payload[:video_title] = "video *bold*"`
      # produces section text containing `video *bold*` raw.
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 1, "video_title" => "video *bold*",
                   "channel_title" => "lab"
                 })
      section_text = described_class.payload_for(n)[:blocks][1][:text][:text]
      expect(section_text).to include("video *bold*")
    end
  end

  describe "icon_url" do
    let(:notification) { create(:notification, :video_published) }

    it "is omitted when credentials carry no value" do
      payload = described_class.payload_for(notification)
      expect(payload).not_to have_key(:icon_url)
    end

    it "is set when credentials carry a value" do
      allow(Rails.application.credentials)
        .to receive(:dig).with(:notifications, :pito_avatar_url)
        .and_return("https://example.com/p.png")
      expect(described_class.payload_for(notification)[:icon_url])
        .to eq("https://example.com/p.png")
    end
  end

  describe "context block" do
    it "carries `<event_type> · <fires_at iso>`" do
      n = create(:notification, :video_published, fires_at: fires_at)
      ctx = described_class.payload_for(n)[:blocks][2][:elements].first[:text]
      expect(ctx).to include("video_published")
      expect(ctx).to include("2026-05-10T12:00:00Z")
    end
  end

  describe "smuggle attempts" do
    it "escapes a Slack `<webhook|spoof>` injected via event_payload" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_id" => 1,
                   "video_title" => "<https://evil.x/spoof|click>",
                   "channel_title" => "lab"
                 })
      section_text = described_class.payload_for(n)[:blocks][1][:text][:text]
      expect(section_text).to include("&lt;https://evil.x/spoof|click&gt;")
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
  # scheme allowlist on `[text](url)` markdown rewritten to Slack
  # `<url|text>` syntax. Bad-scheme URLs collapse to bare escaped
  # text — never reach Slack's link renderer.
  describe "F2 — URL scheme allowlist in rewrite_markdown_links" do
    def call(text)
      described_class.rewrite_markdown_links(text)
    end

    it "strips javascript: scheme to bare text" do
      # The markdown regex rejects parens inside the URL, so
      # `javascript:alert(1)` never matches as a markdown link. The
      # exploit shape the allowlist neutralizes is paren-free.
      out = call("see [click me](javascript:alert@1) now")
      expect(out).to include("click me")
      expect(out).not_to include("<javascript:")
    end

    it "strips data: scheme to bare text" do
      out = call("[xss](data:text/html,whatever)")
      expect(out).to include("xss")
      expect(out).not_to include("<data:")
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
      expect(out).not_to include("<tel:")
    end

    it "preserves http:// links (Slack syntax)" do
      out = call("see [docs](http://example.com/d)")
      expect(out).to include("<http://example.com/d|docs>")
    end

    it "preserves https:// links (Slack syntax)" do
      out = call("see [docs](https://example.com/d)")
      expect(out).to include("<https://example.com/d|docs>")
    end

    it "preserves mailto: links (Slack syntax)" do
      out = call("contact [owner](mailto:owner@example.com)")
      expect(out).to include("<mailto:owner@example.com|owner>")
    end

    it "preserves leading-slash app paths (Slack syntax)" do
      out = call("open [video](/videos/42)")
      expect(out).to include("</videos/42|video>")
    end

    it "strips protocol-relative //evil.com to bare text" do
      out = call("[evil](//evil.com/x)")
      expect(out).to include("evil")
      expect(out).not_to include("<//evil.com")
    end
  end

  # Build a minimum-viable notification for any kind.
  def build_notification_for_kind(kind, fires_at)
    case kind
    when :video_published
      create(:notification, :video_published, fires_at: fires_at,
             event_payload: { "video_id" => 1, "video_title" => "demo",
                              "channel_title" => "lab",
                              "watch_url" => "https://y.com/v" })
    when :video_pre_publish_check_missed
      create(:notification, :video_pre_publish_check_missed, fires_at: fires_at,
             event_payload: { "video_id" => 1, "video_title" => "demo",
                              "missing_checks" => %w[game] })
    when :game_release_upcoming
      create(:notification, :game_release_upcoming, fires_at: fires_at,
             event_payload: { "game_id" => 1, "game_title" => "G",
                              "release_date" => "2026-09-01",
                              "days_until" => 7, "platforms" => [ "PC" ] })
    when :game_release_today
      create(:notification, :game_release_today, fires_at: fires_at,
             event_payload: { "game_id" => 1, "game_title" => "G",
                              "release_date" => "2026-05-10",
                              "platforms" => [ "PC" ] })
    when :milestone_reached
      cal = create(:calendar_entry)
      create(:notification, :milestone_reached, fires_at: fires_at,
             source_calendar_entry: cal,
             event_payload: { "rule_name" => "10k", "metric" => "subs",
                              "threshold" => 10_000,
                              "metric_value_at_fire" => 10_005,
                              "scope_type" => "install",
                              "scope_label" => "this install" })
    when :calendar_entry_firing
      cal = create(:calendar_entry)
      create(:notification, :calendar_entry_firing, fires_at: fires_at,
             source_calendar_entry: cal,
             event_payload: { "entry_id" => cal.id, "title" => "x",
                              "description" => "y" })
    when :sync_error
      create(:notification, :sync_error, fires_at: fires_at,
             event_payload: { "job_class" => "X", "error_class" => "Y",
                              "error_message" => "z" })
    when :youtube_reauth_needed
      create(:notification, :youtube_reauth_needed, fires_at: fires_at,
             event_payload: { "connection_email" => "a@b.com",
                              "connection_id" => 1 })
    end
  end
end
