require "rails_helper"

# Verification sweep (2026-05-10) — focused coverage for the game show
# page's cover meta block + genres/platforms labels.
#
# Existing `games_spec.rb` covers high-level shape (read-only,
# `[edit]` link, no inline form, pane modifiers) but does NOT lock the
# cover-side meta layout:
#   - `released:` / `dev:` / `pub:` render line-by-line, separated by
#     `<br>` inside a single `.text-muted` paragraph.
#   - Missing values are skipped entirely (no `pub: —` placeholder).
#   - The `genres:` and `platforms:` labels under the details pane
#     render as muted `<span class="text-muted">` (matching the
#     ratings / time-to-beat label treatment).
#
# Locking these here means a future copy revamp that reverts to bare
# colon-separated text or strips muting gets caught at request level.
RSpec.describe "Games show meta block + label treatment", type: :request do
  describe "cover meta block (line-by-line)" do
    let!(:platform) { create(:platform, name: "Switch") }
    let!(:developer) { Company.find_or_create_by!(igdb_id: 1) { |c| c.name = "Nintendo EPD" } }
    let!(:publisher) { Company.find_or_create_by!(igdb_id: 2) { |c| c.name = "Nintendo" } }

    let!(:game) do
      g = create(:game, :synced, title: "Zelda BotW", igdb_id: 7346,
                 release_year: 2017,
                 release_date: Date.new(2017, 3, 3))
      GameDeveloper.create!(game: g, company: developer)
      GamePublisher.create!(game: g, company: publisher)
      g.platforms_available << platform
      g
    end

    it "renders `released:`, `dev:`, `pub:` inside one `.text-muted` paragraph" do
      get game_path(game)
      # The block is a single `<p class="text-muted">` carrying the
      # three labelled lines, joined by `<br>` (safe_join + tag.br).
      # Fix 3 (2026-05-11) — released is the full date in `MM-DD-YYYY`.
      meta_paragraph = response.body[/<p class="text-muted"[^>]*>(.*?)<\/p>/m, 1].to_s
      expect(meta_paragraph).to include("released: 03-03-2017")
      expect(meta_paragraph).to include("dev: Nintendo EPD")
      expect(meta_paragraph).to include("pub: Nintendo")
    end

    it "separates the lines with `<br>`" do
      get game_path(game)
      # Pull the meta paragraph and assert `<br>` between two adjacent
      # labels (released → dev) so the line-by-line structure holds.
      expect(response.body).to match(%r{released:\s*03-03-2017\s*<br[^>]*>\s*dev:})
      expect(response.body).to match(/dev:\s*Nintendo EPD\s*<br[^>]*>\s*pub:/)
    end

    it "renders the released date as MM-DD-YYYY (Fix 3, 2026-05-11)" do
      # Boundary case — the formatter must zero-pad both month and day.
      game.update_column(:release_date, Date.new(2021, 1, 4))
      get game_path(game)
      meta_paragraph = response.body[/<p class="text-muted"[^>]*>(.*?)<\/p>/m, 1].to_s
      expect(meta_paragraph).to include("released: 01-04-2021")
    end

    it "does NOT render the legacy year-only `released:` shape" do
      get game_path(game)
      meta_paragraph = response.body[/<p class="text-muted"[^>]*>(.*?)<\/p>/m, 1].to_s
      # The legacy shape was `released: 2017`. Make sure the year alone
      # never appears as the entire released value.
      expect(meta_paragraph).not_to match(/released:\s*2017\s*</)
      expect(meta_paragraph).not_to match(/released:\s*2017\s*<br/)
    end

    it "skips missing release_date entirely (no `released: —` placeholder)" do
      game.update_columns(release_date: nil, release_year: nil)
      get game_path(game)
      meta_paragraph = response.body[/<p class="text-muted"[^>]*>(.*?)<\/p>/m, 1].to_s
      expect(meta_paragraph).not_to match(/released:/)
      # Other labels still render.
      expect(meta_paragraph).to include("dev: Nintendo EPD")
    end

    it "skips missing developer entirely" do
      GameDeveloper.where(game: game).delete_all
      get game_path(game)
      meta_paragraph = response.body[/<p class="text-muted"[^>]*>(.*?)<\/p>/m, 1].to_s
      expect(meta_paragraph).not_to match(/\bdev:/)
      expect(meta_paragraph).to include("pub: Nintendo")
    end

    it "skips missing publisher entirely" do
      GamePublisher.where(game: game).delete_all
      get game_path(game)
      meta_paragraph = response.body[/<p class="text-muted"[^>]*>(.*?)<\/p>/m, 1].to_s
      expect(meta_paragraph).not_to match(/\bpub:/)
      expect(meta_paragraph).to include("dev: Nintendo EPD")
    end

    it "renders multiple developers comma-separated on the dev line" do
      other_dev = Company.find_or_create_by!(igdb_id: 99) { |c| c.name = "Monolith Soft" }
      GameDeveloper.create!(game: game, company: other_dev)
      get game_path(game)
      meta_paragraph = response.body[/<p class="text-muted"[^>]*>(.*?)<\/p>/m, 1].to_s
      expect(meta_paragraph).to match(/dev:\s*(Nintendo EPD,\s*Monolith Soft|Monolith Soft,\s*Nintendo EPD)/)
    end
  end

  describe "genres / platforms labels in the details pane" do
    let!(:game) { create(:game, :synced, title: "G") }
    let!(:genre) { Genre.create!(igdb_id: 5, name: "Adventure") }
    # Use a canonical platform so the canonical-display helper renders
    # it. The label assertion below locks the canonical short name
    # (`Switch2`), not the verbose IGDB-style name. FriendlyId
    # regenerates `slug` from `name` during the save callback, so the
    # canonical slug is pinned with `update_column` after the row
    # persists.
    let!(:platform) do
      p = create(:platform, name: "Nintendo Switch 2", igdb_id: nil)
      p.update_column(:slug, "switch2")
      p.reload
    end

    before do
      game.genres << genre
      game.platforms_available << platform
    end

    # Phase 27 v2 spec 01 — multi-genre `genres:` collapsed to a
    # singular `genre:` label backed by `Game#primary_genre`. The
    # paragraph still wraps the label in `<span class="text-muted">`.
    it "wraps `genre:` in `<span class=\"text-muted\">`" do
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">genre:<\/span>\s*Adventure/)
    end

    it "wraps `platforms:` in `<span class=\"text-muted\">`" do
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">platforms:<\/span>\s*Switch2/)
    end

    it "matches the time-to-beat / ratings table label treatment (text-muted)" do
      get game_path(game)
      # Time-to-beat labels live inside `<td class="text-muted">`. The
      # genre/platforms inline labels use the same `text-muted` token,
      # confirming the visual treatment matches across both surfaces.
      expect(response.body).to include('<td class="text-muted"')
      expect(response.body).to include('<span class="text-muted">genre:')
      expect(response.body).to include('<span class="text-muted">platforms:')
    end

    it "renders `—` placeholder when no primary genre is set" do
      game.update_column(:primary_genre_id, nil)
      game.genres.destroy_all
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">genre:<\/span>\s*—/)
    end

    it "renders `—` placeholder when no platforms are linked" do
      game.platforms_available.destroy_all
      # The canonical-display helper also surfaces Steam from the
      # external_steam_app_id, so clear it (the `:synced` trait stamps
      # one) for this `—` assertion. The `external_gog_id` /
      # `external_epic_id` columns were retired in the 2026-05-17 PC
      # store collapse — only `external_steam_app_id` survives.
      game.update_columns(external_steam_app_id: nil)
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">platforms:<\/span>\s*—/)
    end
  end

  # Phase 27 follow-up (2026-05-11) — canonical short-name display.
  # The show page renders the project's locked short labels (PS5,
  # Switch2, Steam, Xbox), NOT the verbose IGDB names ("PlayStation 5",
  # "Xbox Series X|S", etc.). Phase 27 v2 spec 06 (2026-05-17) PC store
  # collapse — `GoG` + `Epic` labels were retired; the three PC stores
  # converge on `Steam`.
  describe "canonical platform short-names on the show page" do
    # The `:synced` factory trait stamps `external_steam_app_id`, which
    # the canonical-display helper surfaces as "Steam". The tests below
    # clear `external_steam_app_id` so the platform label tracks ONLY
    # what the test exercises (canonical Platform row mapping). The
    # final "full canonical set" test re-stamps it explicitly.
    let!(:game) do
      g = create(:game, :synced, title: "Canonical Test")
      g.update_columns(external_steam_app_id: nil)
      g
    end

    # FriendlyId regenerates slug from name; pin it post-save when the
    # test depends on the canonical slug match (the IGDB-id-based
    # mapping path does not need this).
    def make_platform(name:, slug: nil, igdb_id: nil)
      record = create(:platform, name: name, igdb_id: igdb_id)
      record.update_column(:slug, slug) if slug
      record.reload
    end

    it "renders 'PS5' instead of 'PlayStation 5'" do
      ps5 = make_platform(name: "PlayStation 5", igdb_id: 167)
      game.platforms_available << ps5
      get game_path(game)
      meta = response.body[/platforms:<\/span>\s*([^<]+)/, 1].to_s.strip
      expect(meta).to eq("PS5")
    end

    it "renders 'Xbox' instead of 'Xbox One' or 'Xbox Series X|S'" do
      xbox_one = make_platform(name: "Xbox One", igdb_id: 49)
      xsxs     = make_platform(name: "Xbox Series X|S", igdb_id: 169)
      game.platforms_available << xbox_one
      game.platforms_available << xsxs
      get game_path(game)
      # Collapsed to a single canonical "Xbox" label.
      meta = response.body[/platforms:<\/span>\s*([^<]+)/, 1].to_s.strip
      expect(meta).to eq("Xbox")
    end

    it "drops verbose IGDB names without a canonical alias" do
      ps4 = make_platform(name: "PlayStation 4", igdb_id: 48)
      pc  = make_platform(name: "PC (Microsoft Windows)", igdb_id: 6)
      game.platforms_available << ps4
      game.platforms_available << pc
      get game_path(game)
      meta = response.body[/platforms:<\/span>\s*([^<]+)/, 1].to_s.strip
      expect(meta).to eq("—")
      expect(response.body).not_to include("PC (Microsoft Windows)")
    end

    it "infers 'Steam' from external_steam_app_id even with no canonical Platform row linked" do
      game.update!(external_steam_app_id: "1234")
      get game_path(game)
      meta = response.body[/platforms:<\/span>\s*([^<]+)/, 1].to_s.strip
      expect(meta).to eq("Steam")
    end

    it "renders the full canonical set in locked order" do
      ps5  = make_platform(name: "PlayStation 5", igdb_id: 167)
      sw2  = make_platform(name: "Nintendo Switch 2", slug: "switch2", igdb_id: nil)
      xbox = make_platform(name: "Xbox Series X|S", igdb_id: 169)
      game.platforms_available << ps5
      game.platforms_available << sw2
      game.platforms_available << xbox
      # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — GoG and
      # Epic were retired; the three PC stores converge on Steam. Only
      # `external_steam_app_id` survives; `external_gog_id` /
      # `external_epic_id` are gone.
      game.update!(external_steam_app_id: "1")
      get game_path(game)
      meta = response.body[/platforms:<\/span>\s*([^<]+)/, 1].to_s.strip
      expect(meta).to eq("PS5, Switch2, Steam, Xbox")
    end
  end
end
