require "rails_helper"

# Beta 4 — Phase F1 Lane D (2026-05-20). The legacy bracketed-nav
# header (`[home][calendar] · [channels][videos] · [projects][games] ·
# [notifications]  <spacer>  [settings][_]`) was replaced with the
# `Tui::TopStatusBarComponent`. The old `.nav-row` / `.nav-sep` /
# `.nav-spacer` / `.nav-group` class hooks no longer exist in the
# header — the status bar uses `.sb-bar` / `.sb-left` / `.sb-right`
# instead. The pre-existing test contracts (no separator before
# [settings], inter-group separators, [_] trigger position) are gone
# along with the bracketed nav itself. This spec was rewritten to lock
# the NEW shape:
#
#   * The status bar renders inside `<header>` on every authenticated
#     page (gated by `:hide_chrome` for auth screens).
#   * The bar carries the `tui-status-bar` Stimulus controller +
#     `pito:status_bar` cable channel attribute.
#   * The bar shows the section name on the left (e.g. `home`,
#     `channels`, `games`, `settings`).
#   * No legacy `nav-row` / `nav-sep` / `nav-spacer` markup leaks.
RSpec.describe "Layout top status bar", type: :request do
  def header_html
    body = response.body
    # Slice from the opening <header> to the closing </header> so
    # footer markup (which has its own copyright line) doesn't
    # pollute the assertions.
    match = body.match(%r{<header\b.*?</header>}m)
    expect(match).not_to be_nil, "expected to find <header>...</header> in the response"
    match[0]
  end

  describe "GET /" do
    before { get "/" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    it "renders the new Tui::TopStatusBarComponent inside <header>" do
      header = header_html
      expect(header).to include('class="sb-bar"')
      expect(header).to include('data-controller="tui-status-bar"')
      expect(header).to include('data-cable-channel="pito:status_bar"')
    end

    it "renders the section label on the left for the home section" do
      header = header_html
      # The status bar's section span (`.sb-section`) carries the bare
      # section text — no brackets, no separators. Body's data-section
      # attribute mirrors the same value.
      expect(header).to match(/<span class="sb-section">home/)
    end

    it "drops every legacy bracketed-nav hook (nav-row / nav-sep / nav-spacer)" do
      header = header_html
      expect(header).not_to include('class="nav-row"')
      expect(header).not_to include('class="nav-sep"')
      expect(header).not_to include('class="nav-spacer"')
      # No `[settings]`/`[notifications]`/`[games]` bracketed links in
      # the header anymore — they were replaced by the status bar's
      # section label.
      expect(header).not_to match(/>\[settings\]</)
    end

    it "still mounts the leader-menu controller on <body>" do
      # The `[_]` bracketed trigger that used to live in the navbar's
      # right cluster was dropped. The leader menu is still reachable
      # via the SPACE keypress because the `leader-menu` controller is
      # mounted on `<body>` and registers a document keydown listener.
      expect(response.body).to match(
        /<body[^>]*data-controller="[^"]*\bleader-menu\b[^"]*"/
      )
    end
  end

  describe "GET /channels" do
    before { get "/channels" }

    it "renders the status bar with the channels section label" do
      header = header_html
      expect(header).to include('class="sb-bar"')
      expect(header).to match(/<span class="sb-section">channels/)
    end
  end

  describe "GET /games" do
    before { get "/games" }

    it "renders the status bar with the games section label" do
      header = header_html
      expect(header).to include('class="sb-bar"')
      expect(header).to match(/<span class="sb-section">games/)
    end
  end

  describe "GET /settings" do
    before { get "/settings" }

    it "renders the status bar with the settings section label" do
      header = header_html
      expect(header).to include('class="sb-bar"')
      expect(header).to match(/<span class="sb-section">settings/)
    end
  end
end
