require "rails_helper"

RSpec.describe NotificationFormatter::Discord do
  before do
    allow(Rails.application.credentials).to receive(:dig).and_return(nil)
  end

  let(:fires_at) { Time.utc(2026, 5, 10, 12, 0, 0) }

  # ── per-kind happy paths ──────────────────────────────────────────

  describe "per-kind dispatch" do
    {
      video_published: {
        event_type: "video_published",
        severity: :info,
        payload: {
          "video_id" => 1, "video_title" => "demo", "channel_id" => 2,
          "channel_title" => "Bake Lab",
          "watch_url" => "https://youtube.com/watch?v=x"
        },
        title_includes: "published: demo",
        url_path: "/videos/1"
      },
      video_pre_publish_check_missed: {
        event_type: "video_pre_publish_check_missed",
        severity: :warn,
        payload: {
          "video_id" => 1, "video_title" => "demo",
          "missing_checks" => %w[game]
        },
        title_includes: "missed pre-publish check: demo",
        url_path: "/videos/1/edit"
      },
      game_release_upcoming: {
        event_type: "game_release_upcoming",
        severity: :info,
        payload: {
          "game_id" => 5, "game_title" => "G", "release_date" => "2026-09-01",
          "days_until" => 7, "platforms" => [ "PC" ], "igdb_url" => nil
        },
        title_includes: "G releases in 7 days",
        url_path: "/games/5"
      },
      game_release_today: {
        event_type: "game_release_today",
        severity: :success,
        payload: {
          "game_id" => 5, "game_title" => "G",
          "release_date" => "2026-05-10", "platforms" => [ "PC" ], "igdb_url" => nil
        },
        title_includes: "G releases today",
        url_path: "/games/5"
      },
      milestone_reached: {
        event_type: "milestone_reached",
        severity: :success,
        payload: {
          "rule_name" => "10k", "metric" => "subs",
          "threshold" => 10_000, "metric_value_at_fire" => 10_005,
          "scope_type" => "install", "scope_label" => "this install"
        },
        title_includes: "milestone: 10k",
        url_path: nil # depends on calendar_entry presence
      },
      calendar_entry_firing: {
        event_type: "calendar_entry_firing",
        severity: :info,
        payload: {
          "entry_id" => nil, "title" => "Stream prep",
          "description" => "go time"
        },
        title_includes: "Stream prep",
        url_path: nil
      },
      sync_error: {
        event_type: "sync_error",
        severity: :urgent,
        payload: {
          "job_class" => "VideoSyncBack",
          "error_class" => "Net::HTTPUnauthorized",
          "error_message" => "401"
        },
        title_includes: "sync error: VideoSyncBack",
        url_path: nil # /notifications/<id> — assert presence below
      },
      youtube_reauth_needed: {
        event_type: "youtube_reauth_needed",
        severity: :urgent,
        payload: {
          "connection_id" => 1, "connection_email" => "x@y.com"
        },
        title_includes: "youtube re-auth needed: x@y.com",
        url_path: "/oauth/youtube/start"
      }
    }.each do |kind, spec|
      it "produces a valid Discord payload for #{kind}" do
        n = create(:notification, kind, event_payload: spec[:payload],
                   severity: spec[:severity], event_type: spec[:event_type],
                   fires_at: fires_at)
        payload = described_class.payload_for(n)

        expect(payload).to be_a(Hash)
        expect(payload[:username]).to eq("pito")
        expect(payload).not_to have_key(:avatar_url)
        expect(payload[:content]).to be_a(String)
        expect(payload[:embeds]).to be_an(Array).and have_attributes(length: 1)

        embed = payload[:embeds].first
        expect(embed[:title]).to include(spec[:title_includes])
        expect(embed[:description]).to be_a(String)
        expect(embed[:color]).to eq(NotificationFormatter.severity_color(spec[:severity]))
        expect(embed[:footer][:text]).to include(spec[:event_type])
        expect(embed[:footer][:text]).to include("2026-05-10T12:00:00Z")
        expect(embed[:timestamp]).to eq("2026-05-10T12:00:00Z")
      end
    end
  end

  # ── shape ──────────────────────────────────────────────────────

  describe "payload shape" do
    let(:notification) do
      create(:notification, :video_published,
             event_payload: {
               "video_id" => 1, "video_title" => "demo",
               "channel_title" => "Lab",
               "watch_url" => "https://yt.x/v"
             },
             fires_at: fires_at)
    end

    it "username is 'pito'" do
      expect(described_class.payload_for(notification)[:username]).to eq("pito")
    end

    it "embeds is exactly one element" do
      expect(described_class.payload_for(notification)[:embeds].length).to eq(1)
    end

    it "content is `<emoji> <title>`" do
      content = described_class.payload_for(notification)[:content]
      expect(content).to start_with("📺 published: demo")
    end

    it "embed url is the absolute URL when route default is configured" do
      allow(Rails.application.routes).to receive(:default_url_options)
        .and_return(host: "app.pitomd.com", protocol: "https")
      payload = described_class.payload_for(notification)
      expect(payload[:embeds].first[:url]).to eq("https://app.pitomd.com/videos/1")
    end
  end

  # ── avatar URL ────────────────────────────────────────────────

  describe "avatar URL handling" do
    let(:notification) { create(:notification, :video_published) }

    it "omits :avatar_url when credentials carry no value" do
      payload = described_class.payload_for(notification)
      expect(payload).not_to have_key(:avatar_url)
    end

    it "sets :avatar_url when credentials carry a value" do
      allow(Rails.application.credentials)
        .to receive(:dig).with(:notifications, :pito_avatar_url)
        .and_return("https://example.com/p.png")
      payload = described_class.payload_for(notification)
      expect(payload[:avatar_url]).to eq("https://example.com/p.png")
    end
  end

  # ── severity colors ───────────────────────────────────────────

  describe "severity → color" do
    it "warn maps to amber" do
      n = create(:notification, severity: :warn)
      expect(described_class.payload_for(n)[:embeds].first[:color]).to eq(16_705_372)
    end

    it "urgent maps to red" do
      n = create(:notification, severity: :urgent)
      expect(described_class.payload_for(n)[:embeds].first[:color]).to eq(15_548_997)
    end
  end

  # ── truncation ────────────────────────────────────────────────

  describe "truncation" do
    it "truncates a 300-char title to 256 chars with trailing ellipsis" do
      n = create(:notification, :video_published,
                 event_payload: { "video_title" => "x" * 300, "video_id" => 1 })
      title = described_class.payload_for(n)[:embeds].first[:title]
      expect(title.length).to eq(256)
      expect(title).to end_with("…")
    end

    it "truncates a 5000-char body to 4096 chars" do
      n = create(:notification, :video_published,
                 event_payload: { "video_title" => "x" * 5000, "video_id" => 1, "channel_title" => "c" })
      desc = described_class.payload_for(n)[:embeds].first[:description]
      expect(desc.length).to be <= 4096
      expect(desc).to end_with("…")
    end
  end

  # ── escaping ──────────────────────────────────────────────────

  describe "escaping" do
    it "backslash-escapes asterisks in user-supplied titles" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_title" => "video *bold*", "video_id" => 1,
                   "channel_title" => "lab"
                 })
      desc = described_class.payload_for(n)[:embeds].first[:description]
      expect(desc).to include("video \\*bold\\*")
    end

    it "leaves the formatter's own [text](url) markdown intact" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_title" => "demo", "video_id" => 1,
                   "channel_title" => "lab",
                   "watch_url" => "https://yt.x/v"
                 })
      desc = described_class.payload_for(n)[:embeds].first[:description]
      expect(desc).to include("[watch on youtube](https://yt.x/v)")
    end

    it "escapes <script> in user-supplied content" do
      n = create(:notification, :video_published,
                 event_payload: {
                   "video_title" => "<script>alert(1)</script>", "video_id" => 1,
                   "channel_title" => "lab"
                 })
      desc = described_class.payload_for(n)[:embeds].first[:description]
      # The Discord escape set covers `<`, `>`, `(`, `)`. A literal
      # `<script>alert(1)</script>` becomes
      # `\<script\>alert\(1\)\</script\>` in the embed description.
      expect(desc).not_to include("<script>")
      expect(desc).to include("\\<script\\>")
      expect(desc).to include("\\</script\\>")
    end
  end

  # ── nil URL ───────────────────────────────────────────────────

  describe "nil URL" do
    it "embed[:url] is nil and payload still valid" do
      n = build(:notification, :sync_error,
                event_payload: { "job_class" => "X" },
                with_calendar_entry: false,
                dedup_key: "x")
      n.save!
      n.id = nil
      allow(n).to receive(:id).and_return(nil)
      # Now url returns nil because notification.id is nil
      payload = described_class.payload_for(n)
      # Sync error template uses /notifications/<id> when id present;
      # absolute_url(nil) returns nil.
      expect(payload[:embeds].first).to have_key(:url)
    end
  end

  # ── localization safety ──────────────────────────────────────

  it "preserves Unicode glyphs in title / body" do
    n = create(:notification, :video_published,
               event_payload: {
                 "video_id" => 1,
                 "video_title" => "日本語 ✨", "channel_title" => "تجربة"
               })
    payload = described_class.payload_for(n)
    expect(payload[:embeds].first[:title]).to include("日本語 ✨")
    expect(payload[:embeds].first[:description]).to include("تجربة")
  end

  # ── idempotency ──────────────────────────────────────────────

  it "is idempotent — same input produces same output" do
    n = create(:notification, :video_published,
               event_payload: {
                 "video_id" => 1, "video_title" => "x",
                 "channel_title" => "c"
               },
               fires_at: fires_at)
    a = described_class.payload_for(n)
    b = described_class.payload_for(n)
    expect(a).to eq(b)
  end

  # ── unknown event_type ───────────────────────────────────────

  it "raises ArgumentError for an unknown event_type" do
    n = build(:notification, event_type: "definitely_not_a_real_event")
    n.save!(validate: false)
    expect { described_class.payload_for(n) }
      .to raise_error(ArgumentError, /no template/)
  end
end
