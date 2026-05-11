require "rails_helper"

RSpec.describe "channels/show.html.erb", type: :view do
  before { ChannelSync.clear }

  # The view leans on the channels/* partial set. Render them in
  # production-shape via assigning the channel and asserting on the
  # composed output. The partials themselves are covered in dedicated
  # specs.

  # Mirror ChannelsController#show's aggregate-select / order / limit
  # query so the videos table partial gets the same shape it does in
  # production.
  def channel_videos_relation(channel)
    channel.videos
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
      )
      .group("videos.id")
      .order(Arel.sql("videos.star DESC, COALESCE(videos.published_at, videos.created_at) DESC"))
      .limit(30)
  end

  # Lightweight assign helper — every example assigns at minimum the
  # five instance variables the view reads. Per-example `before` blocks
  # can re-assign individual keys (e.g. give `:channel` a specific
  # factory output).
  def assign_show_defaults(channel)
    assign(:channel, channel)
    assign(:available_channels, Channel.none)
    assign(:youtube_connection, nil)
    assign(:channel_videos, channel_videos_relation(channel))
    assign(:channel_videos_total, channel.videos.count)
  end

  describe "happy path — every column populated" do
    let(:channel) do
      create(:channel,
             title: "Pito Test Channel",
             handle: "@pitotest",
             description: "A devlog about building Pito.\nMore details https://example.test/blog.",
             banner_url: "https://yt3.example.test/banner.jpg",
             avatar_url: "https://yt3.example.test/avatar.jpg",
             links: [
               { "title" => "GitHub", "url" => "https://github.com/example" },
               { "title" => "Blog",   "url" => "https://example.test/blog" }
             ],
             subscriber_count: 12_345,
             view_count: 678_901,
             video_count: 42,
             hidden_subscriber_count: false)
    end

    before { assign_show_defaults(channel) }

    it "renders the H1 with the channel title (no 'channel' prefix)" do
      # 2026-05-11 — the redundant "channel " prefix was dropped.
      render
      expect(rendered).to include("<h1")
      expect(rendered).to include("Pito Test Channel")
      expect(rendered).not_to match(/<h1[^>]*>\s*channel\s+Pito Test Channel/)
    end

    it "renders the empty channel_diff_banner Turbo frame slot" do
      render
      expect(rendered).to match(/<turbo-frame[^>]*id="channel_diff_banner"[^>]*>/)
    end

    it "renders the banner <img>" do
      render
      expect(rendered).to include('src="https://yt3.example.test/banner.jpg"')
    end

    it "renders the avatar <img>" do
      render
      expect(rendered).to include('src="https://yt3.example.test/avatar.jpg"')
    end

    # 2026-05-11 (later) — YouTube-mirror layout regression guards.
    # The detail pane was retuned to match YouTube's channel-header
    # geometry: wide ~6.2:1 banner, 160px circular avatar on the LEFT,
    # large title + muted `@handle · N subscribers · M videos` meta
    # line + description stacked on the RIGHT. Pito monospace +
    # bracketed-link conventions stay; only sizing + positioning
    # mirror YouTube.
    it "wraps the banner in a `.channel-banner` box (CSS anchors the aspect ratio)" do
      render
      expect(rendered).to match(/<div class="channel-banner">/)
      # The inline `max-height: 200px` was the prior banner cap;
      # `aspect-ratio` owns sizing now — fail if it regresses.
      expect(rendered).not_to include("max-height: 200px")
    end

    it "renders the avatar `<img>` with the `.channel-avatar` class (CSS sets 160px circle)" do
      render
      # The avatar carries the `.channel-avatar` class; CSS owns the
      # 160px width/height + `border-radius: 50%` so the markup stays
      # presentational-free. Regression guard against reverting to the
      # inline 64px style.
      expect(rendered).to match(
        /<img[^>]*\b(?:class="channel-avatar"[^>]*src="https:\/\/yt3\.example\.test\/avatar\.jpg"|src="https:\/\/yt3\.example\.test\/avatar\.jpg"[^>]*class="channel-avatar")/
      )
      expect(rendered).not_to include("width: 64px")
    end

    it "renders the headline title in `.channel-headline__title` (large bold via CSS)" do
      render
      expect(rendered).to match(%r{<div class="channel-headline__title">\s*Pito Test Channel\s*</div>})
    end

    it "renders the headline meta line with @handle · N subscribers · M videos" do
      render
      meta_block = rendered[/<div class="channel-headline__meta[^"]*"[^>]*>(.+?)<\/div>/m, 1].to_s
      expect(meta_block).not_to be_empty
      expect(meta_block).to include("@pitotest")
      expect(meta_block).to include("12,345")
      expect(meta_block).to include("subscribers")
      expect(meta_block).to include("42")
      expect(meta_block).to include("videos")
    end

    it "places the description INSIDE the `.channel-headline` column (right of the avatar)" do
      render
      headline_block = rendered[
        /<div class="channel-headline">(.*?)<\/div>\s*<\/div>/m, 1
      ].to_s
      expect(headline_block).to include("A devlog about building Pito.")
    end

    it "renders the avatar BEFORE the headline column in source order (avatar on the LEFT)" do
      render
      identity_block = rendered[/<div class="channel-identity">(.+?)<\/div>\s*<\/div>/m, 1].to_s
      avatar_idx = identity_block.index('class="channel-avatar')
      headline_idx = identity_block.index('class="channel-headline"')
      expect(avatar_idx).not_to be_nil
      expect(headline_idx).not_to be_nil
      expect(avatar_idx).to be < headline_idx
    end

    it "renders the handle" do
      render
      expect(rendered).to include("@pitotest")
    end

    it "renders the [YouTube] outbound link" do
      render
      expect(rendered).to include(">YouTube<")
      expect(rendered).to match(%r{href="https://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}"})
    end

    it "renders the [Studio] outbound link" do
      render
      expect(rendered).to include(">Studio<")
      expect(rendered).to match(%r{href="https://studio\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}"})
    end

    # 2026-05-11 — the `[YouTube]` / `[Studio]` outbound links moved
    # from the detail pane into the H1 row, AFTER the `[+]` add-pane
    # button, separated by a `nav-sep` middle-dot. Regression guard
    # for that placement.
    it "places the [YouTube] link inside the H1 row (after the H1)" do
      render
      h1_row = rendered[/<h1[^>]*>.+?<\/div>/m].to_s
      expect(h1_row).to include(">YouTube<"), "expected [YouTube] inside the H1 row"
    end

    it "places the [Studio] link inside the H1 row (after the H1)" do
      render
      h1_row = rendered[/<h1[^>]*>.+?<\/div>/m].to_s
      expect(h1_row).to include(">Studio<"), "expected [Studio] inside the H1 row"
    end

    it "orders the title row as <title>, [+], separator, [YouTube], [Studio]" do
      # The default fixture assigns an empty Channel.none to
      # @available_channels (no [+] rendered). Re-assign with a real
      # sibling so the [+] button shows up and we can lock the full
      # ordering inside the H1 row.
      sibling = create(:channel)
      assign(:available_channels, [ sibling ])
      render
      h1_row = rendered[/<h1[^>]*>.+?<\/div>/m].to_s
      title_idx       = h1_row.index("Pito Test Channel")
      plus_idx        = h1_row.index(/<span class="bl">\+<\/span>/)
      sep_idx         = h1_row.index('class="nav-sep"')
      yt_channel_idx  = h1_row.index(">YouTube<")
      yt_studio_idx   = h1_row.index(">Studio<")
      expect([ title_idx, plus_idx, sep_idx, yt_channel_idx, yt_studio_idx ]).to all(be_a(Integer))
      expect(title_idx).to      be < plus_idx
      expect(plus_idx).to       be < sep_idx
      expect(sep_idx).to        be < yt_channel_idx
      expect(yt_channel_idx).to be < yt_studio_idx
    end

    it "does NOT render a second [YouTube] link inside the detail pane" do
      render
      # The detail pane (banner + identity + description + links cluster)
      # no longer carries the outbound link cluster. Total occurrences of
      # the label across the page must be exactly one (the H1-row link).
      occurrences = rendered.scan(">YouTube<").size
      expect(occurrences).to eq(1), "expected exactly one [YouTube] link on the page (got #{occurrences})"
    end

    it "opens [YouTube] in a new tab" do
      render
      yt = rendered[/<a[^>]*href="https:\/\/www\.youtube\.com\/channel\/[^"]+"[^>]*>/]
      expect(yt).to include('target="_blank"')
      expect(yt).to include('rel="noopener noreferrer"')
    end

    it "renders the description as plain-text with auto-linked URL" do
      render
      expect(rendered).to include("A devlog about building Pito.")
      expect(rendered).to include('href="https://example.test/blog"')
    end

    it "renders the channel.links jsonb entries" do
      render
      expect(rendered).to include("GitHub")
      expect(rendered).to include("https://github.com/example")
      expect(rendered).to include("Blog")
    end

    it "renders the analytics row with formatted counts (subscribers + views only)" do
      # 2026-05-11 restructure — the `videos` row was dropped from the
      # analytics table. The cached `video_count` is no longer
      # surfaced in this block (the videos table heading carries
      # the count instead).
      render
      analytics_block = rendered[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      expect(analytics_block).to include("12,345")
      expect(analytics_block).to include("678,901")
      expect(analytics_block).to include("subscribers")
      expect(analytics_block).to include("views")
      expect(analytics_block).not_to match(/>\s*videos\s*</)
      expect(analytics_block).not_to include("42")
    end

    it "renders the [full analytics] link to the channel analytics page" do
      render
      expect(rendered).to include("full analytics")
      expect(rendered).to include("href=\"#{channel_analytics_path(channel)}\"")
    end

    it "renders two .pane-row sections (detail, analytics+Google) and a non-pane videos table" do
      # 2026-05-11 follow-up — the analytics pane and the Google
      # pane now share a single pane-row (side-by-side via the
      # existing 2-up grid). The detail row stays on its own.
      # Videos render as a bare table BELOW the two pane-rows.
      render
      expect(rendered.scan(/<div class="pane-row">/).size).to eq(2)
    end

    # 2026-05-11 (width fix) — the row-1 detail pane was switched
    # from `pane--standalone` (auto width that stretches its
    # container) to `pane--wide` (904px = 2 × 452px) so it matches
    # the total width of row 2's two side-by-side `.pane`s
    # (analytics + Google). Regression guard against reverting to
    # `pane--standalone` or any other width modifier on this pane.
    it "renders the row-1 detail pane with `pane--wide` (matches the row-2 double-pane width)" do
      render
      # Find the row-1 pane: the `.pane-row` that contains the
      # `.channel-identity` block (banner + avatar + headline).
      detail_row = rendered[
        /<div class="pane-row">(?:(?!<div class="pane-row">).)*?channel-identity.*?<\/div>\s*<\/div>\s*<\/div>/m
      ]
      expect(detail_row).not_to be_nil,
        "expected to find the row-1 pane-row containing channel-identity"
      detail_pane_classes = detail_row[/<div class="([^"]*)"[^>]*>\s*(?:<%|<div class="channel-banner")/, 1] ||
                            detail_row[/<div class="([^"]*pane[^"]*)"/, 1]
      expect(detail_pane_classes).not_to be_nil,
        "expected the row-1 pane root with a class list"
      classes = detail_pane_classes.split(/\s+/)
      expect(classes).to include("pane"),
        "row-1 detail pane must carry the base `.pane` class"
      expect(classes).to include("pane--wide"),
        "row-1 detail pane must carry `.pane--wide` (904px double-width); got #{detail_pane_classes.inspect}"
      expect(classes).not_to include("pane--standalone"),
        "row-1 detail pane must NOT carry `.pane--standalone` (would auto-stretch and break the row-2 width match)"
    end

    it "places the analytics pane and the Google pane in the SAME pane-row" do
      # The two panes must share a single pane-row container so the
      # CSS grid lays them out side-by-side. Regression guard against
      # the prior layout where each pane sat in its own pane-row and
      # stacked vertically.
      render
      shared_row = rendered[
        /<div class="pane-row">(?:(?!<div class="pane-row">).)*?<h2[^>]*>analytics<\/h2>.*?<h2[^>]*>Google<\/h2>.*?<\/div>\s*<\/div>/m
      ]
      expect(shared_row).not_to be_nil,
        "expected analytics + Google panes to share a single pane-row"
    end

    it "renders the analytics pane BEFORE the Google pane in source order" do
      render
      analytics_idx = rendered.index(/<h2[^>]*>analytics<\/h2>/)
      google_idx = rendered.index(/<h2[^>]*>Google<\/h2>/)
      expect(analytics_idx).not_to be_nil
      expect(google_idx).not_to be_nil
      expect(analytics_idx).to be < google_idx
    end

    # 2026-05-11 (later) — zebra striping regression guards. Each
    # row-2 pane must wear the plain `.pane` class so the workspace
    # `:nth-child(even)` rule paints the right-hand sibling with the
    # contrasting `--color-pane-bg-b` background (matches /settings).
    # `.pane--standalone` would suppress that nth-child rule and
    # collapse both siblings onto the same bg-a tone.
    it "wraps the analytics pane in a plain `.pane` (not `pane--standalone`)" do
      render
      analytics_pane = rendered[/<div class="([^"]*)"[^>]*>\s*<h2[^>]*>analytics<\/h2>/, 1]
      expect(analytics_pane).not_to be_nil
      expect(analytics_pane.split(/\s+/)).to include("pane")
      expect(analytics_pane).not_to include("pane--standalone")
    end

    it "wraps the Google pane in a plain `.pane` (not `pane--standalone`)" do
      render
      # The Google panel partial wraps its content in a single root
      # `<div class="pane" data-google-panel ...>`. Capture the class
      # list off that anchor.
      google_pane = rendered[/<div class="([^"]*)"\s+data-google-panel/, 1]
      expect(google_pane).not_to be_nil
      expect(google_pane.split(/\s+/)).to include("pane")
      expect(google_pane).not_to include("pane--standalone")
    end

    it "places both row-2 panes inside the same `.pane-row` so the zebra rhythm applies" do
      # `:nth-child(even)` only kicks in when both panes are direct
      # children of the same flex container. Regression guard.
      render
      row_html = rendered[
        /<div class="pane-row">(?:(?!<div class="pane-row">).)*?<h2[^>]*>analytics<\/h2>.*?data-google-panel.*?<\/div>\s*<\/div>/m
      ]
      expect(row_html).not_to be_nil,
        "expected analytics + Google panes inside a shared `.pane-row`"
    end

    # 2026-05-11 (height fix) — neither row-2 pane root may carry an
    # inline `margin-bottom`. `.pane-row` is `display: flex` with
    # default `align-items: stretch`, which stretches each item's
    # MARGIN-BOX to the tallest sibling. Asymmetric margins shrink
    # the shorter sibling's visible border-box by exactly that
    # margin, leaving the pane backgrounds bottom-misaligned. The
    # /settings layout never sets `margin-bottom` on `.pane` roots
    # — spacing lives on the inner `<fieldset>` or on the `.pane-row`
    # itself. Mirror that here so the two row-2 panes render at
    # equal visible heights.
    it "renders both row-2 pane roots without inline margin-bottom (preserves flex stretch)" do
      render
      analytics_tag = rendered[/<div class="pane"[^>]*>\s*<h2[^>]*>analytics<\/h2>/]
      expect(analytics_tag).not_to be_nil,
        "expected the analytics pane `<div class=\"pane\">` root tag"
      expect(analytics_tag).not_to match(/margin-bottom\s*:/i),
        "analytics pane root must not carry inline margin-bottom"

      google_tag = rendered[/<div class="pane"[^>]*data-google-panel[^>]*>/]
      expect(google_tag).not_to be_nil,
        "expected the Google pane `<div class=\"pane\" data-google-panel ...>` root tag"
      expect(google_tag).not_to match(/margin-bottom\s*:/i),
        "Google pane root must not carry inline margin-bottom"
    end

    it "renders the chrome row actions: [e], [sync], [-]" do
      render
      # The breadcrumb actions block lives in content_for; the view spec
      # captures it via `content_for(:breadcrumb_actions)`.
      breadcrumb_actions = view.content_for(:breadcrumb_actions).to_s
      expect(breadcrumb_actions).to include("/syncs/channel/#{channel.id}")
      expect(breadcrumb_actions).to include("/deletions/channel/#{channel.id}")
      expect(breadcrumb_actions).to include(edit_channel_path(channel))
    end

    it "does not introduce JS confirm / alert / data-turbo-confirm" do
      render
      expect(rendered).not_to include("data-turbo-confirm")
      expect(rendered).not_to match(/window\.confirm\(/)
      expect(rendered).not_to match(/alert\(/)
    end
  end

  describe "sad path — every nullable column is nil (pre-sync)" do
    let(:channel) { create(:channel) }

    before { assign_show_defaults(channel) }

    it "renders without raising" do
      expect { render }.not_to raise_error
    end

    it "renders the H1 with the 'untitled channel' placeholder" do
      render
      expect(rendered).to include("untitled channel")
    end

    it "hides the banner row entirely (no placeholder per locked decision)" do
      render
      expect(rendered).not_to include('class="channel-banner"')
    end

    it "renders the muted 'no avatar' placeholder" do
      render
      expect(rendered).to include("no avatar")
    end

    it "renders the muted handle placeholder '@—'" do
      render
      expect(rendered).to include("@—")
    end

    it "renders the muted 'no description yet.' caption" do
      render
      expect(rendered).to include("no description yet.")
    end

    it "renders the muted 'no links yet.' caption" do
      render
      expect(rendered).to include("no links yet.")
    end

    it "renders em dashes for subscriber + view counts (videos row dropped)" do
      # 2026-05-11 restructure — the `videos` row was dropped from the
      # analytics table. Pre-sync state surfaces exactly two em-dash
      # placeholders (subscribers + views).
      render
      analytics_block = rendered[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      expect(analytics_block.scan("—").size).to eq(2)
    end

    it "renders the 'no videos yet.' caption" do
      render
      expect(rendered).to include("no videos yet.")
    end

    it "still renders the [full analytics] link" do
      render
      expect(rendered).to include("full analytics")
    end

    it "still renders the [YouTube] and [Studio] links" do
      render
      expect(rendered).to include(">YouTube<")
      expect(rendered).to include(">Studio<")
    end
  end

  describe "edge — hidden subscriber count" do
    let(:channel) { create(:channel, hidden_subscriber_count: true, subscriber_count: 999) }

    before { assign_show_defaults(channel) }

    it "renders 'Hidden' instead of the numeric subscriber count" do
      render
      analytics_block = rendered[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      expect(analytics_block).to include("Hidden")
      expect(analytics_block).not_to include("999")
    end
  end

  describe "edge — empty links array" do
    it "renders the empty caption when links is the empty array" do
      # The column is NOT NULL with default `[]`, so the empty array
      # IS the canonical empty state. Both `nil` (defended at the
      # partial level) and `[]` collapse to the same caption.
      channel = create(:channel, links: [])
      assign_show_defaults(channel.reload)
      render
      expect(rendered).to include("no links yet.")
    end
  end

  describe "edge — videos table heading reflects the live association count" do
    # 2026-05-11 restructure — the analytics block no longer displays
    # the cached `video_count`. The videos table heading is now the
    # single surface where the count appears, and it reflects the
    # live `channel.videos.count` (not the cached column).
    let(:channel) { create(:channel, video_count: 0) }

    before do
      3.times { create(:video, channel: channel) }
      assign_show_defaults(channel)
    end

    it "renders the live videos count (3) in the heading" do
      render
      expect(rendered).to include("videos (3)")
    end

    it "does NOT surface the stale cached video_count (0) in the analytics block" do
      render
      analytics_block = rendered[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      # The videos row is gone; the cached count must not leak into
      # the analytics table.
      expect(analytics_block).not_to match(/>\s*videos\s*</)
    end
  end

  describe "flaw — XSS via title and description" do
    let(:channel) do
      c = create(:channel)
      c.update_columns(
        title: "<script>alert('xss')</script>",
        description: "<script>alert('desc')</script><b>bold</b>"
      )
      c.reload
    end

    before { assign_show_defaults(channel) }

    it "does not render a live <script> tag from the title" do
      render
      # ERB auto-escapes interpolated text. The literal `<script>` from
      # the title column must appear as `&lt;script&gt;` (or stripped),
      # never as a real tag.
      title_block = rendered[/<h1[^>]*>(.+?)<\/h1>/m, 1].to_s
      expect(title_block).not_to include("<script>")
      # The escaped form is acceptable; the parser will treat it as text.
      # Either it's escaped or the helper substitutes the placeholder.
      # The H1 string MUST NOT contain a real script tag.
    end

    it "does not render a live <script> tag from the description" do
      render
      # `simple_format(sanitize: true)` strips the executable
      # `<script>` / `</script>` tags themselves; the inner JS body
      # may survive as literal text but is never parsed as code.
      expect(rendered).not_to include("<script>alert('desc')</script>")
      expect(rendered).not_to include("<script>alert('desc')")
    end

    it "does not crash on XSS-shaped input" do
      expect { render }.not_to raise_error
    end
  end
end
