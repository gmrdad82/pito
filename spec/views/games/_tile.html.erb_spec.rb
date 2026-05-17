require "rails_helper"

# Phase 27 — game tile partial (2026-05-17 footer-drop redesign).
#
# The tile renders:
#
#   cover:  150x200 IMG. Platform logos sit ABSOLUTE on the cover's
#           bottom-right corner inside a `.tile-cover-platforms`
#           container (3 px inset from right/bottom, 2 px gap between
#           logos). Cover container is `position: relative`.
#   line 1: title (single line, ellipsis-truncated if it exceeds the
#           cover width). Rendered BOLD (`.not-released`) when the game
#           is not yet released (release_date nil or in the future) per
#           the 2026-05-11 polish pass (Fix 6).
#
# That's it — the tile footer is title-only as of the 2026-05-17
# footer-drop pass. The `.tile-caption-meta` row (release date + any
# leftover meta segments) is GONE. The platform-logo overlay on
# `.tile-cover-platforms` is an independent surface and still renders
# on the cover.
#
# Historical context (still enforced below where it stops legacy
# layouts from creeping back):
#   - the legacy rating segment is gone (no badge on the tile footer);
#   - the middle-dot separator is gone (no ` · ` between segments);
#   - the previous date row (MM-DD-YYYY / bare year fallback) is gone;
#   - EVERY applicable platform logo renders (multi-logo overlay), not
#     just the first owned/available one.
#
# The :grid variant (default) and :shelf variant share the same
# layout; the only delta is caption font size.
RSpec.describe "games/_tile.html.erb", type: :view do
  # `release_date` is in the past so the tile does NOT get the
  # not-released treatment unless a test specifically overrides it.
  # `external_steam_app_id: nil` overrides the `:synced` trait default
  # so the platform-logo overlay stays off unless a test explicitly
  # attaches platforms — keeps the default `game` let footer-clean.
  let(:game) do
    create(:game, :synced,
           title: "Red Dead Redemption 2",
           release_date: Date.new(2018, 10, 26),
           release_year: 2018,
           igdb_rating: 93,
           external_steam_app_id: nil,
           igdb_id: 5_000_001,
           igdb_slug: "rdr2")
  end

  def render_tile(game, **locals)
    render partial: "games/tile", locals: { game: game, **locals }
  end

  # ------------------------------------------------------------
  # Happy path — title-only caption, no meta row anywhere.
  # ------------------------------------------------------------

  describe "happy: caption renders the title only (no meta row)" do
    before { render_tile(game) }

    it "renders the title in `.tile-caption-title`" do
      expect(rendered).to have_css(".tile-caption-title", text: "Red Dead Redemption 2")
    end

    it "does NOT render any `.tile-caption-meta` row" do
      expect(rendered).not_to have_css(".tile-caption-meta")
    end

    it "does NOT render any `.tile-caption-meta-date` element" do
      expect(rendered).not_to have_css(".tile-caption-meta-date")
    end

    it "does NOT render the release date anywhere in the visible caption" do
      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node.text).not_to include("10-26-2018")
      expect(caption_node.text).not_to include("2018")
    end

    it "preserves the outer `.tile-caption` wrapper" do
      expect(rendered).to have_css(".tile-caption")
    end

    it "does NOT render the rating segment in the visible footer" do
      # The legacy `game_meta_line` plain-text shape is still carried
      # by the anchor's `title=` attribute (the hover-tooltip contract
      # is preserved), but the rendered DOM under `.tile-caption` must
      # NOT include the rating.
      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node.text).not_to include("93")
      expect(rendered).not_to have_css("span.game-rating-badge")
    end

    it "does NOT render the middle-dot separator anywhere in the caption" do
      caption_text = Capybara.string(rendered).find(".tile-caption").text
      expect(caption_text).not_to include("·")
    end

    it "does NOT render the star glyph (Fix 5 — retired)" do
      expect(rendered).not_to include("★")
    end

    it "does NOT include the legacy /100 suffix anywhere on the tile" do
      expect(rendered).not_to include("/100")
    end
  end

  # ------------------------------------------------------------
  # Truncation — title gets ellipsis CSS so long titles don't wrap.
  # ------------------------------------------------------------

  describe "happy: title is single-line with ellipsis truncation" do
    it "applies `white-space: nowrap` to the title line" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:style]).to include("white-space: nowrap")
    end

    it "applies `overflow: hidden` to the title line" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:style]).to include("overflow: hidden")
    end

    it "applies `text-overflow: ellipsis` to the title line" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:style]).to include("text-overflow: ellipsis")
    end

    it "constrains the title `max-width` to the 150px cover width" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:style]).to include("max-width: 150px")
    end

    it "renders an over-long title in full markup (browser truncates via CSS, not the server)" do
      long_title = "The Legend of Zelda: Tears of the Kingdom — Master Edition"
      g = create(:game, :synced,
                 title: long_title,
                 release_date: Date.new(2023, 5, 12),
                 release_year: 2023,
                 igdb_rating: 96,
                 igdb_id: 5_000_002,
                 igdb_slug: "totk-master")

      render_tile(g)

      expect(rendered).to include(long_title)
    end
  end

  # ------------------------------------------------------------
  # 2026-05-17 — `title-tooltip` Stimulus controller wiring on the
  # title span. The controller activates the native `title=`
  # attribute ONLY when the rendered text is truncated
  # (`scrollWidth > clientWidth`); the server-side render only
  # supplies the connect-time wiring + the full-title value, never
  # an unconditional `title=`.
  # ------------------------------------------------------------

  describe "title-tooltip Stimulus controller (tooltip only when truncated)" do
    it "stamps `data-controller=\"title-tooltip\"` on `.tile-caption-title`" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node["data-controller"]).to include("title-tooltip")
    end

    it "stamps `data-title-tooltip-full-title-value` with the full title text" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node["data-title-tooltip-full-title-value"]).to eq("Red Dead Redemption 2")
    end

    it "does NOT carry an unconditional `title=` attribute on the title span (the controller manages it)" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:title]).to be_nil
    end

    it "wires the controller even for long titles (so truncation detection has a hook)" do
      long_title = "The Legend of Zelda: Tears of the Kingdom — Master Edition"
      g = create(:game, :synced,
                 title: long_title,
                 release_date: Date.new(2023, 5, 12),
                 release_year: 2023,
                 igdb_id: 5_000_050,
                 igdb_slug: "totk-tooltip")

      render_tile(g)

      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node["data-controller"]).to include("title-tooltip")
      expect(title_node["data-title-tooltip-full-title-value"]).to eq(long_title)
      expect(title_node[:title]).to be_nil
    end

    it "wires the controller under the :shelf variant too" do
      render_tile(game, variant: :shelf)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node["data-controller"]).to include("title-tooltip")
      expect(title_node["data-title-tooltip-full-title-value"]).to eq("Red Dead Redemption 2")
    end
  end

  # ------------------------------------------------------------
  # Date suppression — both the precise date and the bare-year
  # fallback are gone from the caption regardless of what the
  # record carries.
  # ------------------------------------------------------------

  describe "release date is suppressed in the caption (footer-drop)" do
    it "does NOT render the MM-DD-YYYY string when a precise release_date exists" do
      g = create(:game, :synced,
                 title: "Early-Year Game",
                 release_date: Date.new(2021, 1, 5),
                 release_year: 2021,
                 external_steam_app_id: nil,
                 igdb_id: 5_000_010,
                 igdb_slug: "early-year")

      render_tile(g)

      expect(rendered).not_to include("01-05-2021")
      expect(rendered).not_to have_css(".tile-caption-meta-date")
    end

    it "does NOT fall back to the bare release_year when release_date is nil" do
      g = create(:game, :synced,
                 title: "Year-Only Game",
                 release_date: nil,
                 release_year: 2014,
                 external_steam_app_id: nil,
                 igdb_id: 5_000_011,
                 igdb_slug: "year-only")

      render_tile(g)

      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node.text).not_to include("2014")
      expect(rendered).not_to have_css(".tile-caption-meta-date")
    end
  end

  # ------------------------------------------------------------
  # Sad / edge — missing date, both missing, rating-only.
  # ------------------------------------------------------------

  describe "edge: release_date and release_year both missing" do
    let(:no_date) do
      create(:game, :synced,
             title: "Mystery Game",
             release_date: nil,
             release_year: nil,
             igdb_rating: nil,
             external_steam_app_id: nil,
             igdb_id: 5_001_001,
             igdb_slug: "mystery-no-date")
    end

    it "does NOT render the date span when both fields are nil" do
      render_tile(no_date)
      expect(rendered).not_to have_css(".tile-caption-meta-date")
    end

    it "still does not produce a meta row" do
      render_tile(no_date)
      expect(rendered).not_to have_css(".tile-caption-meta")
    end

    it "still renders the title line" do
      render_tile(no_date)
      expect(rendered).to have_css(".tile-caption-title", text: "Mystery Game")
    end
  end

  describe "edge: rating present but ignored on the tile footer" do
    let(:rating_only) do
      create(:game, :synced,
             title: "Vintage Find",
             release_date: nil,
             release_year: nil,
             igdb_rating: 78,
             external_steam_app_id: nil,
             igdb_id: 5_001_002,
             igdb_slug: "vintage-rating-only")
    end

    it "does NOT render the rating anywhere in the visible caption" do
      render_tile(rating_only)
      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node.text).not_to include("78")
      expect(rendered).not_to have_css("span.game-rating-badge")
    end

    it "produces no meta row when only a rating exists (no date, no logos)" do
      render_tile(rating_only)
      expect(rendered).not_to have_css(".tile-caption-meta")
    end
  end

  # ------------------------------------------------------------
  # Fix 6 — not-yet-released titles render bold.
  # ------------------------------------------------------------

  describe "Fix 6 — not-yet-released title rendering" do
    it "renders BOLD when release_date is in the future" do
      g = create(:game, :synced,
                 title: "Future Game",
                 release_date: Date.current + 30.days,
                 igdb_id: 5_002_001,
                 igdb_slug: "future-game")
      render_tile(g)

      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:class]).to include("not-released")
      expect(title_node[:style]).to include("font-weight: bold")
    end

    it "renders BOLD when release_date is nil (no date set)" do
      g = create(:game, :synced,
                 title: "Unscheduled Game",
                 release_date: nil,
                 igdb_id: 5_002_002,
                 igdb_slug: "unscheduled")
      render_tile(g)

      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:class]).to include("not-released")
      expect(title_node[:style]).to include("font-weight: bold")
    end

    it "does NOT render bold when release_date is today (boundary inclusive)" do
      g = create(:game, :synced,
                 title: "Today Game",
                 release_date: Date.current,
                 igdb_id: 5_002_003,
                 igdb_slug: "today-game")
      render_tile(g)

      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:class]).not_to include("not-released")
      expect(title_node[:style] || "").not_to include("font-weight: bold")
    end

    it "does NOT render bold when release_date is in the past" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:class]).not_to include("not-released")
      expect(title_node[:style] || "").not_to include("font-weight: bold")
    end
  end

  # ------------------------------------------------------------
  # Fix 7 — fallback cover absolute-positions both SVGs so they
  # overlap rather than stacking visually, and inline `display: block`
  # is omitted from the fallback `<img>` tags so the class-level
  # `.game-cover-fallback--dark { display: none }` rule wins.
  # ------------------------------------------------------------

  describe "Fix 7 — missing-cover fallback no longer stacks" do
    let(:no_cover) do
      create(:game,
             title: "No Cover Game",
             cover_image_id: nil,
             igdb_id: nil)
    end

    it "wraps the slot with `position: relative` so absolute children overlap" do
      render_tile(no_cover)
      tile_cover_html = Capybara.string(rendered).find(".tile-cover")["style"]
      expect(tile_cover_html).to include("position: relative")
    end

    it "absolutely positions BOTH fallback SVGs to occupy the same slot" do
      render_tile(no_cover)
      light = Capybara.string(rendered).find(".game-cover-fallback--light")
      dark  = Capybara.string(rendered).find(".game-cover-fallback--dark")
      expect(light[:style]).to include("position: absolute")
      expect(dark[:style]).to include("position: absolute")
    end

    it "does NOT inline `display: block` on the fallback <img> tags" do
      # If `display: block` is inline the class-level `display: none`
      # rule loses the cascade and both SVGs render stacked.
      render_tile(no_cover)
      light = Capybara.string(rendered).find(".game-cover-fallback--light")
      dark  = Capybara.string(rendered).find(".game-cover-fallback--dark")
      expect(light[:style]).not_to include("display: block")
      expect(dark[:style]).not_to include("display: block")
    end
  end

  # ------------------------------------------------------------
  # Variant defaults + shelf-variant typography.
  # ------------------------------------------------------------

  describe "variant defaults" do
    it "defaults to :grid when no variant is provided" do
      render_tile(game)
      expect(rendered).to include('data-variant="grid"')
      expect(rendered).to have_css("a.tile.tile--grid")
    end

    it "accepts variant: :shelf and stamps it on the wrapper" do
      render_tile(game, variant: :shelf)
      expect(rendered).to include('data-variant="shelf"')
      expect(rendered).to have_css("a.tile.tile--shelf")
    end
  end

  describe ":shelf variant uses smaller caption typography" do
    it "shrinks the title font size to 10px under :shelf" do
      render_tile(game, variant: :shelf)
      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node[:style]).to include("font-size: 10px")
    end

    it "keeps the grid variant at 11px for the caption" do
      render_tile(game, variant: :grid)
      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node[:style]).to include("font-size: 11px")
    end
  end

  # ------------------------------------------------------------
  # Linking + keyboard wiring + Turbo Frame escape.
  # ------------------------------------------------------------

  describe "tile remains a single anchor wrapping cover + caption" do
    it "links to game_path(game)" do
      render_tile(game)
      anchor = Capybara.string(rendered).find("a.tile")
      expect(anchor[:href]).to eq(game_path(game))
    end

    it "stamps data-tile-game-id" do
      render_tile(game)
      expect(rendered).to include(%(data-tile-game-id="#{game.id}"))
    end

    it "opts into keyboard grid navigation via data-keyboard-tile" do
      render_tile(game)
      expect(rendered).to include("data-keyboard-tile")
    end

    it "does NOT set an always-on `title=` attribute on the anchor (tooltip-only-when-truncated lives on the title span)" do
      # 2026-05-17 — the legacy always-on `title=` on the anchor
      # (carrying `title + meta line`) is GONE. The hover tooltip is
      # now driven by the `title-tooltip` Stimulus controller attached
      # to `.tile-caption-title`, which only sets `title=` when the
      # rendered text is actually truncated (`scrollWidth >
      # clientWidth`). See
      # `app/javascript/controllers/title_tooltip_controller.js`.
      render_tile(game)
      anchor = Capybara.string(rendered).find("a.tile")
      expect(anchor[:title]).to be_nil
    end

    it "escapes the `games_listing` Turbo Frame via `data-turbo-frame=\"_top\"`" do
      # Without this attribute, clicking a tile inside the
      # `<turbo-frame id=\"games_listing\">` on `/games` would try to
      # match the same frame on `/games/:id` (which has no such
      # frame) and Turbo would render "Content missing". `_top`
      # forces a full-page navigation.
      render_tile(game)
      anchor = Capybara.string(rendered).find("a.tile")
      expect(anchor["data-turbo-frame"]).to eq("_top")
    end
  end

  # ------------------------------------------------------------
  # Flaw assertions — no legacy single-line caption, no reversed
  # order remnants, no leftover middle-dot separator, no resurrected
  # date row.
  # ------------------------------------------------------------

  describe "flaw: pre-2026-05-17 caption layouts are gone" do
    before { render_tile(game) }

    it "does NOT render the legacy `(2018) ★ 93` ordering" do
      expect(rendered).not_to include("(2018) ★ 93")
    end

    it "does NOT render the year parenthesized in the visible caption" do
      caption_text = Capybara.string(rendered).find(".tile-caption").text
      expect(caption_text).not_to include("(2018)")
      expect(caption_text).not_to include("(")
    end

    it "does NOT render the `<rating> · <year>` shape in the visible caption" do
      caption_text = Capybara.string(rendered).find(".tile-caption").text
      expect(caption_text).not_to match(%r{93\s*·\s*2018})
    end
  end

  describe "flaw: meta row stays gone even when logos and a date both apply" do
    it "does NOT resurrect a meta row even when both date and logos are available" do
      # Defensive: a future change that adds platform exposure (logos)
      # must NOT trigger any `.tile-caption-meta` resurrection — the
      # overlay handles all logo rendering, and the date row is gone.
      ps5 = create(:platform, name: "PS5", igdb_id: 167)
      ps5.update_column(:slug, "ps5")
      g = create(:game, :synced,
                 title: "Date + Logos",
                 release_date: Date.new(2022, 6, 1),
                 release_year: 2022,
                 external_steam_app_id: nil,
                 igdb_id: 5_004_001,
                 igdb_slug: "date-logos")
      g.owned_platforms << ps5
      render_tile(g)

      expect(rendered).not_to have_css(".tile-caption-meta")
      expect(rendered).not_to have_css(".tile-caption-meta-date")
      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node.text).not_to include("06-01-2022")
    end
  end

  # ------------------------------------------------------------
  # `item:` alias still works (collection rendering convention).
  # ------------------------------------------------------------

  describe "happy: accepts `item:` local for collection rendering" do
    it "renders the same tile when passed via `item:`" do
      render partial: "games/tile", locals: { item: game }
      expect(rendered).to have_css(".tile-caption-title", text: "Red Dead Redemption 2")
      expect(rendered).not_to have_css(".tile-caption-meta")
    end
  end

  # ------------------------------------------------------------
  # Platform-logo overlay — multi-logo render on the cover's
  # bottom-right corner (2026-05-17 overlay redesign).
  # ------------------------------------------------------------

  describe "platform logo overlay (2026-05-17 multi-logo overlay on cover)" do
    def make_platform(slug:, name: nil, igdb_id: nil)
      record = create(:platform, name: name || "Platform-#{slug}", igdb_id: igdb_id)
      record.update_column(:slug, slug) if slug
      record.reload
    end

    let(:ps5_platform)     { make_platform(slug: "ps5") }
    let(:switch2_platform) { make_platform(slug: "switch2") }
    let(:xbox_platform)    { create(:platform, name: "Xbox One", igdb_id: 49) }

    it "renders the overlay container inside `.tile-cover` (not in `.tile-caption-meta`)" do
      g = create(:game, :synced, title: "PS5 Overlay",
                 external_steam_app_id: nil,
                 igdb_id: 5_010_100, igdb_slug: "ps5-overlay")
      g.owned_platforms << ps5_platform
      render_tile(g)

      # Overlay lives under the cover container.
      expect(rendered).to have_css(".tile-cover .tile-cover-platforms")
      # And does NOT live under any (now non-existent) meta row.
      expect(rendered).not_to have_css(".tile-caption-meta")
    end

    it "appends a 14-px PS5 logo when the game is owned on PS5" do
      g = create(:game, :synced, title: "PS5 Owned",
                 external_steam_app_id: nil,
                 igdb_id: 5_010_001, igdb_slug: "ps5-owned")
      g.owned_platforms << ps5_platform
      render_tile(g)

      overlay = Capybara.string(rendered).find(".tile-cover-platforms")
      # v7 (theme-aware) — the helper emits BOTH color variants; the
      # black one carries the canonical asset path and the alt text.
      img = overlay.find("img.platform-logo--black")
      expect(img[:src]).to eq("/platforms/ps5-16-black.png")
      expect(img[:width]).to eq("14")
      expect(img[:height]).to eq("14")
      expect(img[:alt]).to eq("PS5")

      # White-variant img is present for the dark-theme branch.
      white = overlay.find("img.platform-logo--white")
      expect(white[:src]).to eq("/platforms/ps5-16-white.png")
    end

    it "renders MULTIPLE logos side-by-side when the game spans multiple known platforms" do
      g = create(:game, :synced, title: "Cross-Platform",
                 external_steam_app_id: "999",
                 igdb_id: 5_010_010, igdb_slug: "cross-platform")
      g.owned_platforms << ps5_platform
      g.platforms_available << switch2_platform
      render_tile(g)

      overlay = Capybara.string(rendered).find(".tile-cover-platforms")
      logos = overlay.all("img.platform-logo--black")
      slugs = logos.map { |img| img[:src][%r{/platforms/(.+?)-16-black\.png}, 1] }
      # KNOWN_LOGOS declaration order: ps5, switch2, steam.
      expect(slugs).to eq(%w[ps5 switch2 steam])
    end

    it "renders multiple logo wrappers, one per slug (no joining separator)" do
      g = create(:game, :synced, title: "Two-Platform",
                 external_steam_app_id: nil,
                 igdb_id: 5_010_011, igdb_slug: "two-platform")
      g.owned_platforms << ps5_platform
      g.platforms_available << switch2_platform
      render_tile(g)

      overlay = Capybara.string(rendered).find(".tile-cover-platforms")
      expect(overlay.all(".tile-caption-meta-logo").count).to eq(2)
      expect(overlay.text).not_to include("·")
    end

    it "renders no overlay container for an Xbox-only game (xbox is NOT in KNOWN_LOGOS)" do
      g = create(:game, :synced,
                 title: "Xbox Only", external_steam_app_id: nil,
                 igdb_id: 5_010_003, igdb_slug: "xbox-only")
      g.platforms_available << xbox_platform
      render_tile(g)

      expect(rendered).not_to have_css(".tile-cover-platforms")
    end

    it "renders no overlay container when the game has no platform exposure" do
      # `game` let — no platforms attached.
      render_tile(game)
      expect(rendered).not_to have_css(".tile-cover-platforms")
    end

    it "falls back to platforms_available (unreleased game on PS5)" do
      g = create(:game,
                 title: "Future PS5", release_date: Date.current + 60.days,
                 release_year: nil,
                 igdb_id: 5_010_004, igdb_slug: "future-ps5")
      g.platforms_available << ps5_platform
      render_tile(g)

      overlay = Capybara.string(rendered).find(".tile-cover-platforms")
      img = overlay.find("img.platform-logo--black")
      expect(img[:src]).to eq("/platforms/ps5-16-black.png")
    end

    it "renders the Steam logo when only external_steam_app_id is present (no platforms_available row)" do
      g = create(:game, :synced, title: "Steam-Only Sale",
                 external_steam_app_id: "111",
                 igdb_id: 5_010_005, igdb_slug: "steam-only-sale")
      render_tile(g)

      overlay = Capybara.string(rendered).find(".tile-cover-platforms")
      img = overlay.find("img.platform-logo--black")
      expect(img[:src]).to eq("/platforms/steam-16-black.png")
    end

    it "renders the overlay even when the date is missing (overlay-only platform exposure)" do
      g = create(:game, title: "Naked PS5",
                 igdb_rating: nil, release_date: nil, release_year: nil,
                 igdb_id: 5_010_006, igdb_slug: "naked-ps5")
      g.owned_platforms << ps5_platform
      render_tile(g)

      # Overlay renders on the cover regardless of caption state.
      expect(rendered).to have_css(".tile-cover-platforms")
      overlay = Capybara.string(rendered).find(".tile-cover-platforms")
      expect(overlay).to have_css("img.platform-logo")
      # Meta row never appears.
      expect(rendered).not_to have_css(".tile-caption-meta")
    end
  end

  # ------------------------------------------------------------
  # Overlay positioning — `.tile-cover-platforms` is absolute-
  # positioned inside the relative-positioned cover container.
  # The geometry (flush to bottom-right, 2 px padding, 2 px gap,
  # border-coloured background) lives in
  # `app/assets/tailwind/application.css`; here we assert the
  # structural relationship so the overlay never regresses back
  # into the caption.
  # ------------------------------------------------------------

  describe "overlay positioning relative to the cover container" do
    def make_platform(slug:, name: nil, igdb_id: nil)
      record = create(:platform, name: name || "Platform-#{slug}", igdb_id: igdb_id)
      record.update_column(:slug, slug) if slug
      record.reload
    end

    let(:ps5_platform) { make_platform(slug: "ps5") }

    it "wraps the cover container with `position: relative` so the overlay can absolute-position inside it" do
      g = create(:game, :synced, title: "Overlay Anchor",
                 external_steam_app_id: nil,
                 igdb_id: 5_010_200, igdb_slug: "overlay-anchor")
      g.owned_platforms << ps5_platform
      render_tile(g)

      cover_style = Capybara.string(rendered).find(".tile-cover")["style"]
      expect(cover_style).to include("position: relative")
    end

    it "renders `.tile-cover-platforms` as a DIRECT child of `.tile-cover`" do
      g = create(:game, :synced, title: "Overlay Child",
                 external_steam_app_id: nil,
                 igdb_id: 5_010_201, igdb_slug: "overlay-child")
      g.owned_platforms << ps5_platform
      render_tile(g)

      # `> .tile-cover-platforms` ensures direct parent, not nested.
      expect(rendered).to have_css(".tile-cover > .tile-cover-platforms")
    end
  end
end
