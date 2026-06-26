# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::DetailComponent do
  let(:game) { create(:game, title: "Super Test Game", summary: "A great game.", platforms: %w[PS5 Switch]) }

  # ── Root layout (mobile-first responsive) ─────────────────────────────────

  describe "root layout" do
    it "carries flex-col (mobile-first single-column default)" do
      node = render_inline(described_class.new(game: game))
      root = node.css(".pito-game-detail").first
      expect(root["class"]).to include("flex-col")
    end

    it "carries md:flex-row (desktop two-column at the md: breakpoint)" do
      node = render_inline(described_class.new(game: game))
      root = node.css(".pito-game-detail").first
      expect(root["class"]).to include("md:flex-row")
    end

    it "carries md:items-start (aligns columns at the top on desktop)" do
      node = render_inline(described_class.new(game: game))
      root = node.css(".pito-game-detail").first
      expect(root["class"]).to include("md:items-start")
    end
  end

  # ── Mobile-only column divider (L6) ─────────────────────────────────────────
  # A hairline between the stacked cover and kv-table columns on mobile (<768px),
  # hidden at md: and up where the two-column layout needs no divider.
  describe "mobile-only column divider" do
    it "renders a hairline divider between the columns" do
      node    = render_inline(described_class.new(game: game))
      divider = node.css(".pito-detail-col-divider").first
      expect(divider).not_to be_nil
      expect(divider["class"]).to include("h-px")
    end

    it "is hidden on desktop (carries md:hidden)" do
      node    = render_inline(described_class.new(game: game))
      divider = node.css(".pito-detail-col-divider").first
      expect(divider["class"]).to include("md:hidden")
    end
  end

  # ── Title (now first kv-row in the right column) ───────────────────────────

  describe "title" do
    it "renders a Title label and the game title as the first kv-row in the right column" do
      node = render_inline(described_class.new(game: game))
      grid = node.css(".pito-game-detail__right div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid).not_to be_nil
      expect(grid.text).to include("Title")
      expect(grid.text).to include("Super Test Game")
    end

    it "puts no KV grid in the left column (cover + stats only)" do
      node = render_inline(described_class.new(game: game))
      expect(node.css(".pito-game-detail__left div.grid")).to be_empty
    end

    it "Title row appears before ID row in the kv-table" do
      node = render_inline(described_class.new(game: game))
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.text.index(I18n.t("pito.game.detail.title")))
        .to be < grid.text.index(I18n.t("pito.game.detail.id"))
    end
  end

  # ── ID row ─────────────────────────────────────────────────────────────────

  describe "ID row" do
    it "renders the internal db id, #-prefixed, in the kv-table" do
      node = render_inline(described_class.new(game: game))
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.text).to include(I18n.t("pito.game.detail.id"))
      expect(grid.text).to include("##{game.id}")
    end

    it "wraps the #id in a pito-token-shimmer span" do
      node    = render_inline(described_class.new(game: game))
      id_text = "##{game.id}"
      shimmer = node.css("span.pito-token-shimmer").find { |s| s.text == id_text }
      expect(shimmer).to be_present
    end

    it "wires the #id token to prefill + auto-submit `show game #id`" do
      node    = render_inline(described_class.new(game: game))
      id_text = "##{game.id}"
      span    = node.css("span.pito-token-shimmer").find { |s| s.text == id_text }
      expect(span["data-controller"]).to eq("pito--chat-prefill")
      expect(span["data-action"]).to eq("click->pito--chat-prefill#fill")
      expect(span["data-pito--chat-prefill-text-value"]).to eq("show game ##{game.id}")
      expect(span["data-pito--chat-prefill-submit-value"]).to eq("true")
    end

    it "ID row appears before the Platforms row" do
      g    = create(:game, platforms: [ "PlayStation 5" ])
      node = render_inline(described_class.new(game: g))
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.text.index(I18n.t("pito.game.detail.id")))
        .to be < grid.text.index(I18n.t("pito.game.detail.platforms"))
    end
  end

  # ── Right-column layout order ───────────────────────────────────────────────

  describe "right column layout order" do
    it "kv-table (including ID) appears before Score bar in source order" do
      node  = render_inline(described_class.new(game: game))
      html  = node.css(".pito-game-detail__right").first.inner_html
      expect(html.index("pito-score-bar"))
        .to be > html.index(I18n.t("pito.game.detail.id"))
    end

    it "Score bar appears before Description in source order" do
      node = render_inline(described_class.new(game: game))
      html = node.css(".pito-game-detail__right").first.inner_html
      score_pos = html.index("pito-score-bar")
      desc_pos  = html.index("pito-game-detail__description")
      next if score_pos.nil? || desc_pos.nil?  # description absent → order moot

      expect(score_pos).to be < desc_pos
    end

    it "Description appears after Price (at the bottom)" do
      g    = create(:game, summary: "Epic tale.", price: 59.99)
      node = render_inline(described_class.new(game: g))
      html = node.css(".pito-game-detail__right").first.inner_html
      expect(html.index(I18n.t("pito.game.detail.price")))
        .to be < html.index("pito-game-detail__description")
    end
  end

  # ── Footage row ─────────────────────────────────────────────────────────────

  describe "footage row" do
    it "renders the Footage row with the formatted hours value" do
      g    = create(:game, footage_hours: BigDecimal("12.5"))
      node = render_inline(described_class.new(game: g))
      expect(node.text).to include(I18n.t("pito.game.detail.footage"))
      expect(node.text).to include("12.5h")
    end

    it "renders the Footage row with an em dash when footage_hours is zero" do
      g    = create(:game, footage_hours: 0)
      node = render_inline(described_class.new(game: g))
      expect(node.text).to include(I18n.t("pito.game.detail.footage"))
      expect(node.text).to include("—")
    end

    it "Footage row appears before the Price row in source order" do
      g    = create(:game, footage_hours: BigDecimal("5.0"), price: BigDecimal("59.99"))
      node = render_inline(described_class.new(game: g))
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.text.index(I18n.t("pito.game.detail.footage")))
        .to be < grid.text.index(I18n.t("pito.game.detail.price"))
    end
  end

  # ── Developer / publisher / release / price ────────────────────────────────

  describe "developer names" do
    it "renders developer company names" do
      company = create(:company, name: "Dev Studios")
      create(:game_developer, game: game, company: company)
      game.reload

      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("Dev Studios")
    end
  end

  describe "publisher names" do
    it "renders publisher company names" do
      company = create(:company, name: "Pub Corp")
      create(:game_publisher, game: game, company: company)
      game.reload

      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("Pub Corp")
    end
  end

  describe "release label" do
    it "renders the release label" do
      released_game = create(:game, release_year: 2023, release_month: 3, release_day: 15,
                                    release_date: Date.new(2023, 3, 15))
      node = render_inline(described_class.new(game: released_game))
      expect(node.text).to include("2023")
    end
  end

  describe "last sync at row (C1)" do
    it "renders the IGDB last-sync stamp after Price" do
      g    = create(:game, price: BigDecimal("59.99"), igdb_synced_at: Time.zone.local(2026, 6, 26, 14, 30))
      text = render_inline(described_class.new(game: g)).css(".pito-game-detail__right, .grid").text
      expect(text).to include("Last sync at").and include("26-06-2026 14:30")
    end

    it "renders an em-dash when never IGDB-synced" do
      g = create(:game, igdb_synced_at: nil)
      expect(render_inline(described_class.new(game: g)).text).to include("Last sync at")
    end
  end

  describe "price row" do
    it "renders the Price row with coin glyphs + the number when priced" do
      priced = create(:game, price: BigDecimal("59.99"))
      node   = render_inline(described_class.new(game: priced))
      expect(node.text).to include("Price")
      expect(node.text).to include("59.99")
      expect(node.css("img.pito-coin").size).to eq(3)
      expect(node.to_html).to include("/coin/coin.gif")
    end

    it "renders the FREE star for an explicit 0 price" do
      node = render_inline(described_class.new(game: create(:game, price: 0)))
      expect(node.text).to include("Price")
      expect(node.to_html).to include("/coin/star.gif")
    end

    it "always renders the Price row with an em-dash when unpriced (mirrors Footage)" do
      node = render_inline(described_class.new(game: create(:game, price: nil)))
      expect(node.text).to include("Price")
      expect(node.text).to include("—")
      expect(node.to_html).not_to include("/coin/star.gif")
    end
  end

  # ── Platform icons ──────────────────────────────────────────────────────────

  describe "available platforms (SVG logo icons)" do
    it "renders <img> platform icons for 'PlayStation 4' and 'PC (Microsoft Windows)' (Xbox dropped)" do
      g = create(:game, platforms: [ "PlayStation 4", "PC (Microsoft Windows)", "Xbox One" ])
      node = render_inline(described_class.new(game: g))
      expect(node.css("img.pito-platform-icon").map { |i| i["src"] }).to include("/platforms/playstation.svg")
      expect(node.css("img.pito-platform-icon").map { |i| i["src"] }).to include("/platforms/steam.svg")
      # Xbox One has no matching token — no Xbox icon
      xbox_icons = node.css("img.pito-platform-icon").select { |i| i["src"].include?("xbox") }
      expect(xbox_icons).to be_empty
      # No bordered chips
      expect(node.css("span.border")).to be_empty
    end

    it "de-dupes tokens and renders icons for Switch + Steam" do
      g = create(:game, platforms: [ "Steam", "GOG", "Nintendo Switch" ])
      node = render_inline(described_class.new(game: g))
      srcs = node.css("img.pito-platform-icon").map { |i| i["src"] }
      expect(srcs.count("/platforms/steam.svg")).to eq(1)
      expect(srcs).to include("/platforms/switch.svg")
      expect(node.css("span.border")).to be_empty
    end

    it "renders no platforms row when game.platforms is empty" do
      g = create(:game, platforms: [])
      node = render_inline(described_class.new(game: g))
      expect(node.text).not_to include(I18n.t("pito.game.detail.platforms"))
    end

    it "renders icons inside the KV grid" do
      g = create(:game, platforms: [ "PlayStation 5", "Nintendo Switch" ])
      node = render_inline(described_class.new(game: g))
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.css("img.pito-platform-icon").first).not_to be_nil
    end
  end

  # ── Genres / themes / perspective ──────────────────────────────────────────

  describe "genres" do
    it "renders genre names" do
      genre = create(:genre, name: "Action RPG")
      create(:game_genre, game: game, genre: genre)
      game.reload

      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("Action RPG")
    end
  end

  describe "themes + perspective" do
    it "renders the themes row when present" do
      g = create(:game, themes: [ "Horror", "Survival" ])
      node = render_inline(described_class.new(game: g))
      expect(node.text).to include("Themes")
      expect(node.text).to include("Horror, Survival")
    end

    it "renders the perspective row when present" do
      g = create(:game, player_perspectives: [ "Third person", "First person" ])
      node = render_inline(described_class.new(game: g))
      expect(node.text).to include("Perspective")
      expect(node.text).to include("Third person, First person")
    end

    it "omits both rows when empty" do
      g = create(:game, themes: [], player_perspectives: [])
      node = render_inline(described_class.new(game: g))
      expect(node.text).not_to include("Themes")
      expect(node.text).not_to include("Perspective")
    end
  end

  # ── KV table ───────────────────────────────────────────────────────────────

  describe "KV table (KeyValueRowComponent grid)" do
    it "renders developer row using KeyValueRowComponent (key + value spans)" do
      company = create(:company, name: "Grid Dev")
      create(:game_developer, game: game, company: company)
      game.reload

      node = render_inline(described_class.new(game: game))
      # The grid container must be present
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid).not_to be_nil
      expect(grid.text).to include("Developer")
      expect(grid.text).to include("Grid Dev")
    end

    it "renders the description in the right column under a Description label" do
      g = create(:game, summary: "An epic tale.")
      node = render_inline(described_class.new(game: g))
      right = node.css(".pito-game-detail__right").first
      expect(right).not_to be_nil
      expect(right.text).to include("Description")
      expect(right.text).to include("An epic tale.")
    end
  end

  # ── Score + TTB bars ────────────────────────────────────────────────────────

  describe "score bar" do
    it "embeds the ScoreBarComponent (pito-score-bar marker class)" do
      node = render_inline(described_class.new(game: game))
      expect(node.css(".pito-score-bar").first).not_to be_nil
    end
  end

  describe "time-to-beat component with footage tick" do
    it "embeds the TTB component including the footage mark" do
      game.update!(footage_hours: 2)

      node = render_inline(described_class.new(game: game))
      # Footage uses the ScoreBar-style ▼ value bubble, not a | tick.
      bubble = node.css(".pito-ttb__footage-bubble").first
      expect(bubble).not_to be_nil
      # The bubble's value reflects the game's footage_hours via FootageHours.
      expect(bubble.text).to include("2h")
    end
  end

  # ── Intro timestamp inline flow ─────────────────────────────────────────────

  describe "intro timestamp inline flow" do
    let(:node_with_intro) { render_inline(described_class.new(game: game, intro: "Test intro line")) }

    it "intro div is inline-flow (not flex) so the timestamp leads the copy and long copy wraps beneath it" do
      intro = node_with_intro.css(".pito-game-detail__intro").first
      expect(intro["class"]).not_to include("flex")
    end

    it "timestamp slot is a direct child of the intro flex container (no block boundary)" do
      slot = node_with_intro.css(".pito-game-detail__intro > [data-pito-ts-slot]").first
      expect(slot).not_to be_nil
    end

    it "intro copy text is present inside the intro flex container" do
      intro = node_with_intro.css(".pito-game-detail__intro").first
      expect(intro.text).to include("Test intro line")
    end

    it "renders an html_safe intro (subject-shimmer span) raw, not escaped" do
      html  = Pito::Copy.render_html("pito.copy.game.detail_intro", { title: game.title }, shimmer: [ :title ])
      node  = render_inline(described_class.new(game: game, intro: html))
      intro = node.css(".pito-game-detail__intro").first
      expect(intro.css("span.pito-subject-shimmer").map(&:text)).to include(game.title)
    end
  end

  # ── Cover art ───────────────────────────────────────────────────────────────

  describe "cover art" do
    context "when no cover art is attached" do
      it "renders the no_cover placeholder" do
        node = render_inline(described_class.new(game: game))
        expect(node.text).to include(I18n.t("pito.game.detail.no_cover"))
      end
    end

    context "when the variant call raises a StandardError" do
      it "cover_art_url returns nil (the rescue block swallows the error)" do
        # Use a plain double for cover_art that raises on #variant (via method_missing).
        # ActiveStorage::Attached::One delegates variant via method_missing; a
        # duck-type double is the most reliable way to stub that call path.
        cover_double = double("cover_art", variant: nil) # :nodoc:
        allow(cover_double).to receive(:variant).and_raise(StandardError, "variant failed")
        component = described_class.new(game: game)
        allow(component).to receive(:cover_art_attached?).and_return(true)
        allow(game).to receive(:cover_art).and_return(cover_double)
        expect(component.cover_art_url).to be_nil
      end
    end
  end

  # ── Cover art: Ken-Burns pan (bounded box + animation hook) ─────────────────
  #
  # Layout contract:
  #   - .pito-game-detail__cover is the 374×210 overflow-hidden bounding box
  #     (same footprint as the show-video thumbnail). CSS sets width/height/overflow.
  #   - When cover art is attached the <img> carries class `pito-cover-pan`,
  #     which CSS animates with a slow vertical translateY ping-pong.
  #   - When /config fx is off OR prefers-reduced-motion is set, CSS disables
  #     the animation and locks the image at translateY(0) (top-anchored).
  #     There is no separate DOM class for the static state — CSS handles it via
  #     @media (prefers-reduced-motion: reduce) and
  #     html:has(#pito-settings[data-fx="false"]) .pito-cover-pan { animation: none }.
  #   - When no cover art is attached the placeholder <div> carries neither
  #     `pito-cover-pan` nor any animation class.

  describe "cover art Ken-Burns pan" do
    context "when cover art is attached" do
      before do
        allow_any_instance_of(described_class).to receive(:cover_art_attached?).and_return(true)
        allow_any_instance_of(described_class).to receive(:detail_cover_url).and_return("/covers/test.jpg")
      end

      it "renders the cover inside the .pito-game-detail__cover bounding box" do
        node = render_inline(described_class.new(game: game))
        cover = node.css(".pito-game-detail__cover").first
        expect(cover).not_to be_nil
      end

      it "the cover <img> carries the pito-cover-pan animation class" do
        node = render_inline(described_class.new(game: game))
        img  = node.css(".pito-game-detail__cover img").first
        expect(img).not_to be_nil
        expect(img["class"]).to include("pito-cover-pan")
      end

      it "the cover <img> also carries the block display class" do
        node = render_inline(described_class.new(game: game))
        img  = node.css(".pito-game-detail__cover img.pito-cover-pan").first
        expect(img["class"]).to include("block")
      end
    end

    context "when no cover art is attached (placeholder)" do
      it "the placeholder div does not carry the pito-cover-pan class" do
        node = render_inline(described_class.new(game: game))
        # No img rendered, so .pito-cover-pan must be absent
        expect(node.css(".pito-cover-pan")).to be_empty
      end

      it "the cover container still renders (holds the placeholder text)" do
        node = render_inline(described_class.new(game: game))
        cover = node.css(".pito-game-detail__cover").first
        expect(cover).not_to be_nil
        expect(cover.text).to include(I18n.t("pito.game.detail.no_cover"))
      end
    end
  end

  # ── Edge cases ──────────────────────────────────────────────────────────────

  describe "rendering with nil score" do
    it "does not raise when game.score is nil" do
      game.update_column(:score, nil)
      expect { render_inline(described_class.new(game: game.reload)) }.not_to raise_error
    end
  end

  describe "empty associations" do
    it "does not crash when developer_companies is empty" do
      expect { render_inline(described_class.new(game: game)) }.not_to raise_error
    end

    it "omits the developer row when no developers" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).not_to include(I18n.t("pito.game.detail.developer"))
    end

    it "does not crash when publisher_companies is empty" do
      expect { render_inline(described_class.new(game: game)) }.not_to raise_error
    end

    it "omits the publisher row when no publishers" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).not_to include(I18n.t("pito.game.detail.publisher"))
    end

    it "omits the genres row when no genres" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).not_to include(I18n.t("pito.game.detail.genres"))
    end
  end

  # ── Left column: stats counters ─────────────────────────────────────────────

  describe "left column stats counters" do
    let(:channel) { create(:channel) }

    context "with linked videos that have stats" do
      let(:vid1) { create(:video, channel: channel) }
      let(:vid2) { create(:video, channel: channel) }

      before do
        create(:video_game_link, video: vid1, game: game)
        create(:video_game_link, video: vid2, game: game)
        Pito::Stats.set(vid1, :views,    1_000)
        Pito::Stats.set(vid1, :likes,      200)
        Pito::Stats.set(vid1, :comments,    50)
        Pito::Stats.set(vid2, :views,      500)
        Pito::Stats.set(vid2, :likes,      100)
        Pito::Stats.set(vid2, :comments,    20)
        game.reload
      end

      it "renders the stats counters div in the left column" do
        node = render_inline(described_class.new(game: game))
        expect(node.css(".pito-game-detail__stats")).not_to be_empty
      end

      it "does not bold the Stats heading (J19 — normal weight)" do
        node    = render_inline(described_class.new(game: game))
        heading = node.css(".pito-game-detail__stats-heading").first
        expect(heading["class"]).not_to include("font-bold")
      end

      it "shows summed view count formatted via CompactCount (1 000 + 500 = 1 500 → 1.5K)" do
        node = render_inline(described_class.new(game: game))
        left = node.css(".pito-game-detail__left").first
        expect(left.text).to include("1.5K")
      end

      it "shows summed like count (200 + 100 = 300)" do
        node = render_inline(described_class.new(game: game))
        left = node.css(".pito-game-detail__left").first
        expect(left.text).to include("300")
      end

      it "shows summed comment count (50 + 20 = 70)" do
        node = render_inline(described_class.new(game: game))
        left = node.css(".pito-game-detail__left").first
        expect(left.text).to include("70")
      end
    end

    context "with no linked videos" do
      it "shows 0 for each counter" do
        node = render_inline(described_class.new(game: game))
        left = node.css(".pito-game-detail__left").first
        # three zeros — views, likes, comments
        expect(left.text.scan("0").length).to be >= 3
      end
    end

    it "renders the Views word and likes/comments icons" do
      node  = render_inline(described_class.new(game: game))
      stats = node.css(".pito-game-detail__stats").first
      expect(stats.text).to include("Views")
      labels = stats.css("svg").map { |s| s["aria-label"] }
      expect(labels).to include("Likes").and include("Comments")
    end

    it "does not render a per-game stats legend line (removed in refactor)" do
      node = render_inline(described_class.new(game: game))
      expect(node.css(".pito-game-detail__legend")).to be_empty
    end
  end

  # ── Left column: Shinies block ──────────────────────────────────────────────

  describe "Shinies block" do
    context "with achievements" do
      # views lane: multiple thresholds — only the max (1K) should render.
      let!(:views_small) do
        create(:achievement, achievable: game, metric: "views", threshold: 1,
                             unlocked_at: 4.weeks.ago)
      end
      let!(:views_max) do
        create(:achievement, achievable: game, metric: "views", threshold: 1_000,
                             unlocked_at: 2.days.ago)
      end
      # likes lane: single threshold (100) — the max and only badge for this metric.
      let!(:likes_max) do
        create(:achievement, achievable: game, metric: "likes", threshold: 100,
                             unlocked_at: 1.day.ago)
      end

      it "renders the shinies heading in the left column" do
        node = render_inline(described_class.new(game: game))
        expect(node.css(".pito-game-detail__shinies-heading")).not_to be_empty
      end

      it "renders exactly one badge per metric (2 total — views and likes)" do
        node = render_inline(described_class.new(game: game))
        expect(node.css(".pito-achievement-badge").length).to eq(2)
      end

      it "shows the max-threshold badge for views (1K Views, not the lower threshold)" do
        node  = render_inline(described_class.new(game: game))
        texts = node.css(".pito-achievement-badge").map(&:text)
        expect(texts.any? { |t| t.include?("1K") && t.include?("Views") }).to be true
      end

      it "shows the max-threshold badge for likes (100 Likes)" do
        node  = render_inline(described_class.new(game: game))
        texts = node.css(".pito-achievement-badge").map(&:text)
        expect(texts.any? { |t| t.include?("100") && t.include?("Likes") }).to be true
      end

      it "renders badges ordered by recency of their lane — likes (1 day ago) before views (2 days ago)" do
        node        = render_inline(described_class.new(game: game))
        shinies_div = node.css(".pito-game-detail__shinies").first
        text        = shinies_div.text
        # likes max (1 day ago) is more recent; views max (2 days ago) is older
        # anchor on threshold values (100 Likes vs 1K Views) which are unambiguous
        expect(text.index("100")).to be < text.index("1K")
      end

      it "renders the shinies block inside the left column" do
        node = render_inline(described_class.new(game: game))
        left = node.css(".pito-game-detail__left").first
        expect(left.css(".pito-game-detail__shinies")).not_to be_empty
      end

      it "does not bold the Shinies heading (J19 — normal weight)" do
        node    = render_inline(described_class.new(game: game))
        heading = node.css(".pito-game-detail__shinies-heading").first
        expect(heading["class"]).not_to include("font-bold")
      end

      it "renders detail-card badges in compact form — no unlock date span (J11/J18)" do
        node   = render_inline(described_class.new(game: game))
        badges = node.css(".pito-game-detail__shinies .pito-achievement-badge")
        badges.each do |badge|
          expect(badge.css(".pito-achievement-badge__date")).to be_empty
        end
      end

      it "lays out badges in a left-aligned flex-wrap container" do
        node    = render_inline(described_class.new(game: game))
        shinies = node.css(".pito-game-detail__shinies").first
        expect(shinies["class"]).to include("flex-wrap")
        expect(shinies["class"]).not_to include("justify-center")
      end

      it "does not render a Shinies legend (removed in the metric-display overhaul)" do
        node = render_inline(described_class.new(game: game))
        expect(node.css(".pito-game-detail__shinies-legend")).to be_empty
      end
    end

    context "without achievements" do
      it "does not render the shinies block" do
        node = render_inline(described_class.new(game: game))
        expect(node.css(".pito-game-detail__shinies")).to be_empty
      end

      it "does not render the shinies heading" do
        node = render_inline(described_class.new(game: game))
        expect(node.css(".pito-game-detail__shinies-heading")).to be_empty
      end

      it "does not render the Shinies legend" do
        node = render_inline(described_class.new(game: game))
        expect(node.css(".pito-game-detail__shinies-legend")).to be_empty
      end
    end
  end
end
