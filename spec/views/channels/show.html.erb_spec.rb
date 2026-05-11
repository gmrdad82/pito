require "rails_helper"

RSpec.describe "channels/show.html.erb", type: :view do
  before { ChannelSync.clear }

  # The view leans on the channels/* partial set. Render them in
  # production-shape via assigning the channel and asserting on the
  # composed output. The partials themselves are covered in dedicated
  # specs.

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

    before do
      assign(:channel, channel)
      assign(:available_channels, Channel.none)
    end

    it "renders the H1 with the channel title" do
      render
      expect(rendered).to include("<h1")
      expect(rendered).to include("Pito Test Channel")
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

    it "renders the handle" do
      render
      expect(rendered).to include("@pitotest")
    end

    it "renders the [youtube channel] outbound link" do
      render
      expect(rendered).to include("youtube channel")
      expect(rendered).to match(%r{href="https://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}"})
    end

    it "renders the [youtube studio] outbound link" do
      render
      expect(rendered).to include("youtube studio")
      expect(rendered).to match(%r{href="https://studio\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}"})
    end

    it "opens [youtube channel] in a new tab" do
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

    it "renders the analytics row with formatted counts" do
      render
      expect(rendered).to include("12,345")
      expect(rendered).to include("678,901")
      expect(rendered).to include("42")
      expect(rendered).to include("subscribers")
      expect(rendered).to include("views")
      expect(rendered).to include("videos")
    end

    it "renders the [full analytics] link to the channel analytics page" do
      render
      expect(rendered).to include("full analytics")
      expect(rendered).to include("href=\"#{channel_analytics_path(channel)}\"")
    end

    it "renders three .pane-row sections (detail, analytics, videos)" do
      render
      expect(rendered.scan(/<div class="pane-row">/).size).to eq(3)
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

    before do
      assign(:channel, channel)
      assign(:available_channels, Channel.none)
    end

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

    it "renders em dashes for subscriber / view / video counts" do
      render
      # Three rows × one em dash each = 3 occurrences within the
      # analytics block.
      analytics_block = rendered[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      expect(analytics_block.scan("—").size).to eq(3)
    end

    it "renders the 'no videos yet.' caption" do
      render
      expect(rendered).to include("no videos yet.")
    end

    it "still renders the [full analytics] link" do
      render
      expect(rendered).to include("full analytics")
    end

    it "still renders the [youtube channel] and [youtube studio] links" do
      render
      expect(rendered).to include("youtube channel")
      expect(rendered).to include("youtube studio")
    end
  end

  describe "edge — hidden subscriber count" do
    let(:channel) { create(:channel, hidden_subscriber_count: true, subscriber_count: 999) }

    before do
      assign(:channel, channel)
      assign(:available_channels, Channel.none)
    end

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
      assign(:channel, channel.reload)
      assign(:available_channels, Channel.none)
      render
      expect(rendered).to include("no links yet.")
    end
  end

  describe "edge — video_count cached column lags videos association" do
    let(:channel) { create(:channel, video_count: 0) }

    before do
      3.times { create(:video, channel: channel) }
      assign(:channel, channel)
      assign(:available_channels, Channel.none)
    end

    it "renders the actual videos pane count (3), not the stale cached value (0)" do
      render
      expect(rendered).to include("videos (3)")
    end

    it "still renders the analytics row's video_count from the cached column (0)" do
      render
      analytics_block = rendered[/<h2[^>]*>analytics<\/h2>(.+?)<\/table>/m, 1].to_s
      expect(analytics_block).to include("0")
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

    before do
      assign(:channel, channel)
      assign(:available_channels, Channel.none)
    end

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
