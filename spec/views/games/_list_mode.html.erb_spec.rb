require "rails_helper"

# Phase 27 — 01d. List display mode partial (post 2026-05-11 polish v2).
#
# Flat alphabetically-sorted table. Columns (locked, post-polish v2):
#
#   select | cover | title | genre | released | rating | owned
#
# Key changes in the 2026-05-11 v2 polish pass (Fixes 4 + 5):
#   * `genres` column renamed `genre` (singular — primary genre only).
#   * `platforms owned` column renamed `owned`.
#   * Reorder: `genre` moved between `title` and `released`.
#   * Bulk-select cell now carries REAL `<input type="checkbox">`
#     elements (header + per-row) wired to the `bulk-select` Stimulus
#     controller. `[ ]` / `[x]` glyph rendering is delegated to
#     `CheckboxComponent` (which renders an `md-check-indicator` span).
#   * The list-mode section is wrapped in a `bulk-select` controller
#     so a `[sync N]` + `[delete N]` toolbar appears when at least one
#     row is selected.
RSpec.describe "games/_list_mode.html.erb", type: :view do
  def render_list(games)
    render partial: "games/list_mode", locals: { games: games }
  end

  describe "happy path — locked column order + heading" do
    it "renders the post-polish heading 'all' (Fix 8)" do
      render_list(Game.none)
      expect(rendered).to match(%r{<h2[^>]*>\s*all\s*</h2>})
      expect(rendered).not_to match(%r{<h2[^>]*>\s*all games\s*</h2>})
    end

    it "renders the seven post-polish v2 table headers in the locked column order" do
      create(:game, :synced, title: "Alpha", igdb_id: 4_100_001,
             igdb_slug: "alpha-list")
      render_list(Game.all)

      doc = Nokogiri::HTML.fragment(rendered)
      # The first header cell now carries the CheckboxComponent (which
      # injects a `<label>` wrapper with internal whitespace), so we
      # strip the cell's text content for the comparison. The
      # checkbox-bearing cell collapses to "" once stripped.
      headers = doc.css("thead tr th").map { |th| th.text.strip }
      # 2026-05-11 polish v2 — order is: select / cover / title /
      # genre / released / rating / owned. Renames: `genres` → `genre`
      # (singular), `platforms owned` → `owned`.
      expect(headers).to eq([
        "", "", "title", "genre", "released", "rating", "owned"
      ])
    end

    it "does NOT render a `status` column (Fix 3)" do
      create(:game, :synced, title: "Statusless", igdb_id: 4_100_002,
             igdb_slug: "statusless-list")
      render_list(Game.all)

      expect(rendered).not_to match(%r{<th[^>]*>\s*status\s*</th>})
      expect(rendered).not_to include("status-cell")
    end

    it "right-aligns the released + rating columns via .num" do
      create(:game, :synced, title: "Aligned Hdr", igdb_id: 4_100_004,
             igdb_slug: "aligned-hdr-list")
      render_list(Game.all)

      # `.num` is stamped on both the released and rating headers.
      released_header = rendered[%r{<th class="num">\s*released\s*</th>}]
      rating_header   = rendered[%r{<th class="num">\s*rating\s*</th>}]
      expect(released_header).not_to be_nil
      expect(rating_header).not_to be_nil
    end

    it "links each title to /games/:slug without inline year" do
      game = create(:game, :synced, title: "Linked Game", igdb_id: 4_100_031,
                    igdb_slug: "linked-list-game",
                    release_date: Date.new(2022, 6, 1),
                    release_year: 2022)
      render_list(Game.all)

      expect(rendered).to include(%(href="#{game_path(game)}"))
      expect(rendered).to include("Linked Game")
      title_cell_match = rendered[%r{<td class="title-cell">.*?</td>}m]
      expect(title_cell_match).not_to include("(2022)")
    end

    it "stamps data-display-mode=\"list\" on the section" do
      render_list(Game.none)
      expect(rendered).to include('data-display-mode="list"')
    end
  end

  describe "Fix 4 — released column renders full mm-dd-yyyy date" do
    it "renders the release_date as mm-dd-yyyy" do
      create(:game, :synced, title: "Dated", igdb_id: 4_100_041,
             igdb_slug: "dated-list",
             release_date: Date.new(2018, 3, 27))
      render_list(Game.all)

      cell = rendered[%r{<td class="released-cell[^"]*"[^>]*>.*?</td>}m]
      expect(cell).to include("03-27-2018")
    end

    it "renders an em-dash when release_date is nil" do
      create(:game, title: "Undated", igdb_id: nil, release_date: nil)
      render_list(Game.all)

      cell = rendered[%r{<td class="released-cell[^"]*"[^>]*>.*?</td>}m]
      expect(cell).to include("—")
    end

    it "applies the `.num` class so the cell right-aligns" do
      create(:game, :synced, title: "Aligned", igdb_id: 4_100_044,
             igdb_slug: "aligned-list",
             release_date: Date.new(2020, 12, 31))
      render_list(Game.all)

      expect(rendered).to match(%r{<td class="released-cell num[^"]*"})
    end
  end

  describe "Fix 2 (2026-05-11) — rating renders as colored bold integer" do
    it "renders the rating as a bare integer (no /100 suffix)" do
      create(:game, :synced, title: "Rated Hit", igdb_id: 4_100_051,
             igdb_slug: "rated-hit-list", igdb_rating: 88)
      render_list(Game.all)

      cell = rendered[%r{<td class="rating-cell[^"]*"[^>]*>.*?</td>}m]
      expect(cell).to include(">88<")
      expect(cell).not_to include("/100")
    end

    it "renders the rating inside a Games::RatingBadgeComponent span" do
      create(:game, :synced, title: "Tiered", igdb_id: 4_100_056,
             igdb_slug: "tiered-list", igdb_rating: 88)
      render_list(Game.all)
      doc = Nokogiri::HTML.fragment(rendered)

      badge = doc.css("td.rating-cell span.game-rating-badge").first
      expect(badge).not_to be_nil
      expect(badge["class"]).to include("game-rating-badge--good")
      expect(badge["style"]).to include("color: var(--color-rating-good)")
      expect(badge["style"]).to include("font-weight: bold")
    end

    it "does NOT render the star glyph in the rating cell" do
      create(:game, :synced, title: "Starless", igdb_id: 4_100_052,
             igdb_slug: "starless-list", igdb_rating: 88)
      render_list(Game.all)

      cell = rendered[%r{<td class="rating-cell[^"]*"[^>]*>.*?</td>}m]
      expect(cell).not_to include("★")
    end

    it "renders an em-dash when igdb_rating is nil" do
      create(:game, title: "Unrated", igdb_id: nil, igdb_rating: nil)
      render_list(Game.all)

      cell = rendered[%r{<td class="rating-cell[^"]*"[^>]*>.*?</td>}m]
      expect(cell).to include("—")
    end

    it "applies the `.num` class so the cell right-aligns" do
      create(:game, :synced, title: "Aligned R", igdb_id: 4_100_055,
             igdb_slug: "aligned-r-list", igdb_rating: 75)
      render_list(Game.all)

      expect(rendered).to match(%r{<td class="rating-cell num})
    end
  end

  describe "Fix 6 — bold for not-yet-released titles" do
    it "stamps `.not-released` on the title <a> when release_date is in the future" do
      g = create(:game, :synced, title: "Future Title", igdb_id: 4_100_061,
                 igdb_slug: "future-title-list",
                 release_date: Date.current + 30.days)
      render_list(Game.all)

      anchor = Capybara.string(rendered).find(%(a[href="#{game_path(g)}"]))
      expect(anchor[:class]).to include("not-released")
    end

    it "stamps `.not-released` when release_date is nil" do
      g = create(:game, :synced, title: "Undated Title", igdb_id: 4_100_062,
                 igdb_slug: "undated-title-list",
                 release_date: nil)
      render_list(Game.all)

      anchor = Capybara.string(rendered).find(%(a[href="#{game_path(g)}"]))
      expect(anchor[:class]).to include("not-released")
    end

    it "does NOT stamp `.not-released` on past-release titles" do
      g = create(:game, :synced, title: "Released Title", igdb_id: 4_100_063,
                 igdb_slug: "released-title-list",
                 release_date: Date.new(2018, 5, 1))
      render_list(Game.all)

      anchor = Capybara.string(rendered).find(%(a[href="#{game_path(g)}"]))
      expect(anchor[:class].to_s).not_to include("not-released")
    end
  end

  describe "v2 — bulk-select header + per-row real checkboxes" do
    it "renders a `<th class=\"select-cell\">` as the first header" do
      create(:game, :synced, title: "Selectable", igdb_id: 4_100_071,
             igdb_slug: "selectable-list")
      render_list(Game.all)

      expect(rendered).to match(%r{<thead>\s*<tr>\s*<th class="select-cell"})
    end

    it "renders a real `<input type=\"checkbox\">` header (select-all)" do
      create(:game, :synced, title: "Pickable", igdb_id: 4_100_072,
             igdb_slug: "pickable-list")
      render_list(Game.all)
      doc = Nokogiri::HTML.fragment(rendered)

      header = doc.css('thead input[type="checkbox"][data-bulk-select-target="headerCheckbox"]')
      expect(header.length).to eq(1)
      expect(header.first["data-action"]).to include("bulk-select#toggleAll")
    end

    it "renders a real `<input type=\"checkbox\">` per row, value = game id" do
      g = create(:game, :synced, title: "Per Row", igdb_id: 4_100_073,
                 igdb_slug: "per-row-list")
      render_list(Game.all)
      doc = Nokogiri::HTML.fragment(rendered)

      row_box = doc.css('tbody tr.game-row input[type="checkbox"][data-bulk-select-target="checkbox"]').first
      expect(row_box).not_to be_nil
      expect(row_box["value"]).to eq(g.id.to_s)
      expect(row_box["data-action"]).to include("bulk-select#toggle")
    end

    it "wraps the section in a `bulk-select` Stimulus controller targeting game" do
      create(:game, :synced, title: "Wrapped", igdb_id: 4_100_074,
             igdb_slug: "wrapped-list")
      render_list(Game.all)

      expect(rendered).to include('data-controller="bulk-select"')
      expect(rendered).to include('data-bulk-select-delete-type-value="game"')
      expect(rendered).to include('data-bulk-select-sync-type-value="game"')
    end

    it "renders the bulk-toolbar shell with sync + delete action targets" do
      create(:game, :synced, title: "Toolbar", igdb_id: 4_100_075,
             igdb_slug: "toolbar-list")
      render_list(Game.all)
      doc = Nokogiri::HTML.fragment(rendered)

      toolbar = doc.css(".games-bulk-toolbar").first
      expect(toolbar).not_to be_nil
      expect(toolbar.css('[data-bulk-select-target="syncAction"]').length).to eq(1)
      expect(toolbar.css('[data-bulk-select-target="deleteAction"]').length).to eq(1)
    end

    it "stamps each row with a starting job state of `idle`" do
      g = create(:game, :synced, title: "Idle Row", igdb_id: 4_100_076,
                 igdb_slug: "idle-row-list")
      render_list(Game.all)
      doc = Nokogiri::HTML.fragment(rendered)

      row = doc.css("tr.game-row[data-game-id='#{g.id}']").first
      expect(row).not_to be_nil
      expect(row["data-game-job-state"]).to eq("idle")
    end
  end

  describe "no letter-group spacer rows" do
    it "does not render `tr.letter-head` rows even with multiple buckets" do
      create(:game, :synced, title: "Apex Legends", igdb_id: 4_100_011,
             igdb_slug: "apex-legends-list")
      create(:game, :synced, title: "Borderlands", igdb_id: 4_100_012,
             igdb_slug: "borderlands-list")
      create(:game, :synced, title: "Cuphead", igdb_id: 4_100_014,
             igdb_slug: "cuphead-list")

      render_list(Game.all)

      expect(rendered).not_to include('class="letter-head"')
      expect(rendered).not_to include("data-letter=")
      expect(rendered).not_to include("position: sticky")
      expect(rendered).not_to include("background: #fff")
    end

    it "still sorts titles alphabetically across buckets" do
      create(:game, :synced, title: "Borderlands", igdb_id: 4_100_012,
             igdb_slug: "borderlands-list")
      create(:game, :synced, title: "Apex Legends", igdb_id: 4_100_011,
             igdb_slug: "apex-legends-list")
      create(:game, :synced, title: "Cuphead", igdb_id: 4_100_013,
             igdb_slug: "cuphead-list")

      render_list(Game.all)

      apex_pos = rendered.index("Apex Legends")
      border_pos = rendered.index("Borderlands")
      cup_pos = rendered.index("Cuphead")

      expect(apex_pos).to be < border_pos
      expect(border_pos).to be < cup_pos
    end
  end

  describe "genres column — primary genre only" do
    it "renders a single short-form name (not a comma-joined list)" do
      game = create(:game, :synced, title: "Multi Genre", igdb_id: 4_200_010,
                    igdb_slug: "multi-genre-list")
      rpg = create(:genre, name: "Role-playing (RPG)", igdb_id: 9_311)
      adv = create(:genre, name: "Adventure", igdb_id: 9_312)
      shooter = create(:genre, name: "Shooter", igdb_id: 9_313)
      create(:game_genre, game: game, genre: rpg)
      create(:game_genre, game: game, genre: adv)
      create(:game_genre, game: game, genre: shooter)

      render_list(Game.all)

      genres_cell = rendered[%r{<td class="genre-cell"[^>]*>.*?</td>}m]
      expect(genres_cell).not_to include(", ")
    end

    it "applies the short-form mapping (Role-playing (RPG) → RPG)" do
      game = create(:game, :synced, title: "RPG Game", igdb_id: 4_200_001,
                    igdb_slug: "rpg-list-game")
      rpg = create(:genre, name: "Role-playing (RPG)", igdb_id: 9_301)
      create(:game_genre, game: game, genre: rpg)

      render_list(Game.all)

      expect(rendered).to include("RPG")
      expect(rendered).not_to include("Role-playing (RPG)")
    end

    it "renders unmapped genre names as-is" do
      game = create(:game, :synced, title: "Adventure Game", igdb_id: 4_200_002,
                    igdb_slug: "adventure-list-game")
      adventure = create(:genre, name: "Adventure", igdb_id: 9_302)
      create(:game_genre, game: game, genre: adventure)

      render_list(Game.all)

      expect(rendered).to include("Adventure")
    end

    it "renders an em-dash when the game has no genres" do
      create(:game, :synced, title: "Bare Game", igdb_id: 4_200_003,
             igdb_slug: "bare-list-game")
      render_list(Game.all)

      genres_cell = rendered[%r{<td class="genre-cell"[^>]*>.*?</td>}m]
      expect(genres_cell).to include("—")
    end
  end

  describe "Fix 4 (2026-05-11) — inline `<style>` block migrated to application.css" do
    # The d123fbb hygiene sweep moved the per-partial `<style>` rules
    # into `app/assets/tailwind/application.css`. Selectors are
    # preserved verbatim — see the `.games-list-mode` block in the
    # stylesheet. The list partial no longer emits a `<style>` tag.
    it "does NOT emit a `<style>` block in the partial output" do
      create(:game, title: "No Inline Style", igdb_id: nil)
      render_list(Game.all)
      expect(rendered).not_to include("<style>")
    end

    it "does NOT inline `display: block` on the cover-cell img" do
      create(:game, title: "No Cover 2", igdb_id: nil)
      render_list(Game.all)
      expect(rendered).not_to include("object-fit: cover; display: block;")
    end
  end

  describe "Fix 1 (2026-05-11) — pinned column widths via <colgroup>" do
    # Column widths are sourced from `--col-width-*` CSS variables so
    # one edit propagates across listing surfaces. The partial emits a
    # `<colgroup>` whose seven `<col>` classes map to the variables.
    it "renders a `<colgroup>` with seven `<col>` children" do
      create(:game, :synced, title: "Cols", igdb_id: 4_100_077,
             igdb_slug: "cols-list")
      render_list(Game.all)
      doc = Nokogiri::HTML.fragment(rendered)

      cols = doc.css("table.list-table > colgroup > col")
      expect(cols.length).to eq(7)
      classes = cols.map { |c| c["class"] }
      expect(classes).to eq(%w[
        col-select col-cover col-title col-genre col-released col-rating col-owned
      ])
    end
  end

  describe "edge cases" do
    it "renders gracefully when a game has no release_date / rating / genres" do
      create(:game, title: "Bare Row", igdb_id: nil)

      expect { render_list(Game.all) }.not_to raise_error
      # All three "empty" cells render an em-dash placeholder.
      expect(rendered.scan("—").length).to be >= 3
    end

    it "renders the theme-aware SVG fallback pair when a game has no cover_image_id" do
      create(:game, title: "No Cover", igdb_id: nil)
      render_list(Game.all)

      expect(rendered).not_to include("[no cover]")
      expect(rendered).to include("game-cover-fallback--light")
      expect(rendered).to include("game-cover-fallback--dark")
      expect(rendered).to match(%r{game_cover_fallback_shelf_light(-[a-f0-9]+)?\.svg})
      expect(rendered).to match(%r{game_cover_fallback_shelf_dark(-[a-f0-9]+)?\.svg})
    end

    it "sinks non-alphabetic titles to the bottom of the sort order" do
      create(:game, :synced, title: "2048", igdb_id: 4_101_001,
             igdb_slug: "two-zero-list")
      create(:game, :synced, title: "Apex", igdb_id: 4_101_003,
             igdb_slug: "apex-sink-list")

      render_list(Game.all)

      expect(rendered.index("Apex")).to be < rendered.index("2048")
    end
  end

  describe "empty state" do
    it "shows the muted no-match copy when given an empty relation" do
      render_list(Game.none)
      expect(rendered).to include("no games match this filter.")
      expect(rendered).not_to include('class="letter-head"')
      expect(rendered).not_to include('class="game-row"')
    end
  end
end
