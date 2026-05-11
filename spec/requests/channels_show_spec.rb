require "rails_helper"

# Phase 7.5 §11b — request-level coverage for the revamped
# `/channels/:slug` page. Complements the view + partial specs by
# walking the full controller → view stack and asserting on the
# response body. The legacy two-pane URL+videos surface tests in
# `spec/requests/channels_spec.rb` were superseded by 11b; the
# tests below are the canonical contract.
RSpec.describe "GET /channels/:slug — show page revamp", type: :request do
  before { ChannelSync.clear }

  let(:hydrated_channel) do
    create(:channel,
           title: "Pito Test Channel",
           handle: "@pitotest",
           description: "A devlog about building Pito.\nMore at https://example.test/blog.",
           banner_url: "https://yt3.example.test/banner.jpg",
           avatar_url: "https://yt3.example.test/avatar.jpg",
           links: [
             { "title" => "GitHub", "url" => "https://github.com/example" }
           ],
           subscriber_count: 12_345,
           view_count: 678_901,
           video_count: 42,
           hidden_subscriber_count: false)
  end

  describe "happy — every column populated" do
    it "returns 200" do
      get channel_path(hydrated_channel)
      expect(response).to have_http_status(:ok)
    end

    it "renders the H1 with the channel title (no 'channel' prefix)" do
      # 2026-05-11 — the redundant "channel " prefix was dropped from
      # the H1 and breadcrumb leaf. The `[channels]` breadcrumb segment
      # already communicates the section.
      get channel_path(hydrated_channel)
      expect(response.body).to match(/<h1[^>]*>Pito Test Channel<\/h1>/)
      expect(response.body).to include("Pito Test Channel")
    end

    it "does not prefix the H1 with the literal word 'channel'" do
      get channel_path(hydrated_channel)
      expect(response.body).not_to match(/<h1[^>]*>\s*channel\s+Pito Test Channel/)
    end

    it "does not prefix the breadcrumb leaf with the literal word 'channel'" do
      get channel_path(hydrated_channel)
      # BreadcrumbComponent renders inside `<nav class="dot-list">`.
      # The leaf is the last item; it should read just the title.
      html = Nokogiri::HTML.fragment(response.body)
      breadcrumb_html = html.css("nav.dot-list").to_html
      expect(breadcrumb_html).to include("Pito Test Channel")
      expect(breadcrumb_html).not_to match(/channel\s+Pito Test Channel/)
    end

    it "exposes the empty channel_diff_banner Turbo frame slot" do
      get channel_path(hydrated_channel)
      expect(response.body).to match(/<turbo-frame[^>]*id="channel_diff_banner"[^>]*>/)
    end

    it "renders two pane rows (detail, analytics+Google) and a videos table outside any pane" do
      # 2026-05-11 follow-up — the analytics pane and the Google
      # connection pane now share one pane-row (side-by-side via
      # the existing 2-up grid). The detail row stays on its own,
      # so the page has two pane-rows total. Videos render below
      # as a bare /videos-style table.
      get channel_path(hydrated_channel)
      expect(response.body.scan(/<div class="pane-row">/).size).to eq(2)
    end

    it "places the analytics pane and the Google connection pane in the SAME pane-row" do
      # Regression guard: the two panes must share a single
      # pane-row container so the CSS grid lays them out
      # side-by-side instead of stacking vertically.
      get channel_path(hydrated_channel)
      shared_row = response.body[
        /<div class="pane-row">(?:(?!<div class="pane-row">).)*?<h2[^>]*>analytics<\/h2>.*?<h2[^>]*>Google connection<\/h2>.*?<\/div>\s*<\/div>/m
      ]
      expect(shared_row).not_to be_nil,
        "expected analytics + Google connection panes to share a single pane-row"
    end

    it "renders the analytics pane BEFORE the Google connection pane in source order" do
      get channel_path(hydrated_channel)
      analytics_idx = response.body.index("<h2 style=\"margin: 0 0 8px 0;\">analytics</h2>")
      google_idx = response.body.index("<h2 style=\"margin: 0 0 8px 0;\">Google connection</h2>")
      expect(analytics_idx).not_to be_nil
      expect(google_idx).not_to be_nil
      expect(analytics_idx).to be < google_idx
    end

    it "drops the 'videos' row from the analytics table" do
      get channel_path(hydrated_channel)
      analytics_block = response.body[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      expect(analytics_block).to include("subscribers")
      expect(analytics_block).to include("views")
      expect(analytics_block).not_to match(/>\s*videos\s*</)
    end

    it "renders the videos table heading after the last pane row" do
      get channel_path(hydrated_channel)
      videos_idx = response.body.index(/<h2[^>]*>videos \(/)
      expect(videos_idx).not_to be_nil
      last_pane_row_idx = response.body.rindex('<div class="pane-row">')
      expect(last_pane_row_idx).not_to be_nil
      expect(videos_idx).to be > last_pane_row_idx
    end

    it "renders the [YouTube] outbound link" do
      get channel_path(hydrated_channel)
      expect(response.body).to include(">YouTube<")
      # Anchor with both the YT URL href and target=_blank somewhere in
      # its attribute list. Attribute order is Rails-determined, so
      # match each piece independently against the same tag.
      yt_anchor = response.body[/<a [^>]*href="https:\/\/www\.youtube\.com\/channel\/UC[A-Za-z0-9_-]{22}"[^>]*>/]
      expect(yt_anchor).not_to be_nil
      expect(yt_anchor).to include('target="_blank"')
      expect(yt_anchor).to include('rel="noopener noreferrer"')
    end

    it "renders the [Studio] outbound link" do
      get channel_path(hydrated_channel)
      expect(response.body).to include(">Studio<")
      studio_anchor = response.body[/<a [^>]*href="https:\/\/studio\.youtube\.com\/channel\/UC[A-Za-z0-9_-]{22}"[^>]*>/]
      expect(studio_anchor).not_to be_nil
      expect(studio_anchor).to include('target="_blank"')
    end

    it "renders the [full analytics] link" do
      get channel_path(hydrated_channel)
      expect(response.body).to include("full analytics")
      expect(response.body).to include("href=\"#{channel_analytics_path(hydrated_channel)}\"")
    end

    it "does NOT render the [see all videos] link when the channel has <=30 videos" do
      # `hydrated_channel` is created without any associated videos, so
      # the video count is 0 and the [see all videos] link must not
      # render — the table already shows everything (nothing, in this
      # case).
      get channel_path(hydrated_channel)
      expect(response.body).not_to include("see all videos")
    end

    it "renders the [see all videos] link when the channel has >30 videos" do
      31.times { create(:video, channel: hydrated_channel) }
      get channel_path(hydrated_channel)
      expect(response.body).to include("see all videos")
      expect(response.body).to include("href=\"#{videos_path(channel: hydrated_channel.to_param)}\"")
    end

    it "renders the existing chrome — [e], [sync], [-]" do
      get channel_path(hydrated_channel)
      expect(response.body).to include(edit_channel_path(hydrated_channel))
      expect(response.body).to include("/syncs/channel/#{hydrated_channel.id}")
      expect(response.body).to include("/deletions/channel/#{hydrated_channel.id}")
    end

    # Phase 11i Q7 follow-up — single-channel `[sync]` carries
    # `intent=diff_check` so the POST enqueues `ChannelDiffCheckJob`
    # instead of fanning through `BulkSyncJob → ChannelSync` (the cache
    # overwrite path). Cron-driven `ChannelSync` is unchanged.
    it "the [sync] link uses intent=diff_check (compare YouTube, not overwrite cache)" do
      get channel_path(hydrated_channel)
      expect(response.body).to include("/syncs/channel/#{hydrated_channel.id}?intent=diff_check")
    end

    it "does not introduce JS confirm / alert / data-turbo-confirm" do
      get channel_path(hydrated_channel)
      expect(response.body).not_to include("data-turbo-confirm")
      expect(response.body).not_to match(/window\.confirm\(/)
    end

    it "renders bracketed labels without inner padding spaces" do
      get channel_path(hydrated_channel)
      # Per project rule A — labels read `[YouTube]` not
      # `[ YouTube ]`.
      expect(response.body).not_to match(/\[\s+<span class="bl">YouTube/)
      expect(response.body).not_to match(/\[\s+<span class="bl">full analytics/)
    end
  end

  describe "sad — pre-sync channel (every nullable column nil)" do
    let(:bare_channel) { create(:channel) }

    it "returns 200" do
      get channel_path(bare_channel)
      expect(response).to have_http_status(:ok)
    end

    it "renders 'untitled channel' in the H1" do
      get channel_path(bare_channel)
      expect(response.body).to include("untitled channel")
    end

    it "hides the banner row entirely" do
      get channel_path(bare_channel)
      expect(response.body).not_to include('class="channel-banner"')
    end

    it "renders the 'no avatar' placeholder" do
      get channel_path(bare_channel)
      expect(response.body).to include("no avatar")
    end

    it "renders the muted handle placeholder" do
      get channel_path(bare_channel)
      expect(response.body).to include("@—")
    end

    it "renders 'no description yet.'" do
      get channel_path(bare_channel)
      expect(response.body).to include("no description yet.")
    end

    it "renders 'no links yet.'" do
      get channel_path(bare_channel)
      expect(response.body).to include("no links yet.")
    end

    it "renders em dashes in the analytics row (subscribers, views — two cells)" do
      # 2026-05-11 restructure — the `videos` row was dropped from the
      # analytics table, so a pre-sync channel surfaces exactly two
      # em-dash placeholders (subscribers + views).
      get channel_path(bare_channel)
      analytics_block = response.body[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      expect(analytics_block.scan("—").size).to eq(2)
    end

    it "renders 'no videos yet.'" do
      get channel_path(bare_channel)
      expect(response.body).to include("no videos yet.")
    end
  end

  describe "edge — empty links jsonb" do
    let(:channel) { create(:channel, links: []) }

    it "returns 200 and renders the empty-state caption" do
      get channel_path(channel)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no links yet.")
    end
  end

  describe "edge — hidden_subscriber_count" do
    let(:channel) { create(:channel, hidden_subscriber_count: true, subscriber_count: 999) }

    it "renders 'Hidden' instead of the numeric count" do
      get channel_path(channel)
      analytics_block = response.body[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      expect(analytics_block).to include("Hidden")
      expect(analytics_block).not_to include("999")
    end
  end

  describe "flaw — XSS in title and description" do
    let(:channel) do
      c = create(:channel)
      c.update_columns(
        title: "<script>alert('t')</script>",
        description: "<script>alert('d')</script><b>bold</b>"
      )
      c
    end

    it "returns 200 (does not crash)" do
      get channel_path(channel)
      expect(response).to have_http_status(:ok)
    end

    it "does NOT contain a live <script> tag from the title or description" do
      get channel_path(channel)
      # The body may contain `<script>` from legitimate sources (e.g.
      # importmap shim). The guarantee is that the user-provided
      # payload never appears as an executable `<script>` tag:
      #   - For the title, ERB auto-escapes — the literal `<script>`
      #     comes out as `&lt;script&gt;`.
      #   - For the description, `simple_format(sanitize: true)` strips
      #     the executable `<script>` tags themselves.
      # The inner JS body may survive as literal text after the
      # sanitizer strip, but is never parsed.
      expect(response.body).not_to include("<script>alert('t')</script>")
      expect(response.body).not_to include("<script>alert('d')</script>")
      expect(response.body).not_to include("<script>alert('t')")
      expect(response.body).not_to include("<script>alert('d')")
    end
  end

  describe "redirect — integer id resolves to canonical slug URL" do
    let(:channel) { create(:channel) }

    it "redirects /channels/<id> to /channels/<slug> (existing canonical-slug behavior)" do
      get "/channels/#{channel.id}"
      expect(response).to have_http_status(:moved_permanently).or have_http_status(:found)
      expect(response.headers["Location"]).to include(channel.to_param)
    end
  end

  describe "404 — unknown slug" do
    it "returns 404 for an unknown slug" do
      get "/channels/UCdoesnotexistxxxxxxxxxxxx"
      expect(response).to have_http_status(:not_found)
    end
  end
end
