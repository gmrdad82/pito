require "rails_helper"

# Header navbar layout (2026-05-10 follow-up). The right-aligned
# `[settings][logout]` cluster sits flush against the navbar's
# right edge — the `.nav-spacer` flex item is the visual separator,
# so there must be NO `.nav-sep` (center-dot `·`) immediately
# before the right cluster. The other inter-group separators
# (after [home][calendar], after [channels][videos], after
# [projects][games]) stay.
RSpec.describe "Layout navbar separators", type: :request do
  def header_html
    body = response.body
    # Slice from the opening <header> to the closing </header> so
    # footer separators (which intentionally exist) don't pollute
    # the assertions.
    match = body.match(%r{<header\b.*?</header>}m)
    expect(match).not_to be_nil, "expected to find <header>...</header> in the response"
    match[0]
  end

  describe "GET /" do
    before { get "/" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    it "does not render a separator immediately before the [settings] link in the header" do
      header = header_html
      spacer_at = header.index('class="nav-spacer"')
      settings_at = header.index(">settings<")
      expect(spacer_at).not_to be_nil
      expect(settings_at).not_to be_nil

      between = header[spacer_at..settings_at]
      expect(between).not_to include('class="nav-sep"'),
        "found a .nav-sep between the nav spacer and the right cluster; " \
        "expected the right cluster to sit flush with no leading dot"
    end

    it "still renders the inter-group separators between the left/middle groups" do
      header = header_html
      # The header should still contain `.nav-sep` separators between
      # [home][calendar] / [channels][videos] / [projects][games] /
      # [notifications]. With the trailing one removed the count drops
      # from 4 to 3.
      sep_count = header.scan(/class="nav-sep[^"]*"/).size
      expect(sep_count).to eq(3)
    end

    it "renders the [settings] and [logout] right cluster" do
      header = header_html
      expect(header).to include(">settings<")
      expect(header).to include(">logout<")
    end

    it "renders the nav spacer that right-anchors the cluster" do
      expect(header_html).to include('class="nav-spacer"')
    end
  end

  describe "GET /channels" do
    before { get "/channels" }

    it "does not render a separator immediately before the [settings] link in the header" do
      header = header_html
      spacer_at = header.index('class="nav-spacer"')
      settings_at = header.index(">settings<")
      expect(spacer_at).not_to be_nil
      expect(settings_at).not_to be_nil

      between = header[spacer_at..settings_at]
      expect(between).not_to include('class="nav-sep"')
    end
  end
end
