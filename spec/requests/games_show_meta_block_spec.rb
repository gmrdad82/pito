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
                 release_year: 2017)
      GameDeveloper.create!(game: g, company: developer)
      GamePublisher.create!(game: g, company: publisher)
      g.platforms_available << platform
      g
    end

    it "renders `released:`, `dev:`, `pub:` inside one `.text-muted` paragraph" do
      get game_path(game)
      # The block is a single `<p class="text-muted">` carrying the
      # three labelled lines, joined by `<br>` (safe_join + tag.br).
      meta_paragraph = response.body[/<p class="text-muted"[^>]*>(.*?)<\/p>/m, 1].to_s
      expect(meta_paragraph).to include("released: 2017")
      expect(meta_paragraph).to include("dev: Nintendo EPD")
      expect(meta_paragraph).to include("pub: Nintendo")
    end

    it "separates the lines with `<br>`" do
      get game_path(game)
      # Pull the meta paragraph and assert `<br>` between two adjacent
      # labels (released → dev) so the line-by-line structure holds.
      expect(response.body).to match(/released:\s*2017\s*<br[^>]*>\s*dev:/)
      expect(response.body).to match(/dev:\s*Nintendo EPD\s*<br[^>]*>\s*pub:/)
    end

    it "skips missing release_year entirely (no `released: —` placeholder)" do
      game.update_column(:release_year, nil)
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
    # (`Switch2`), not the verbose IGDB-style name.
    let!(:platform) { create(:platform, name: "Nintendo Switch 2", slug: "switch2", igdb_id: nil) }

    before do
      game.genres << genre
      game.platforms_available << platform
    end

    it "wraps `genres:` in `<span class=\"text-muted\">`" do
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">genres:<\/span>\s*Adventure/)
    end

    it "wraps `platforms:` in `<span class=\"text-muted\">`" do
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">platforms:<\/span>\s*Switch2/)
    end

    it "matches the time-to-beat / ratings table label treatment (text-muted)" do
      get game_path(game)
      # Time-to-beat labels live inside `<td class="text-muted">`. The
      # genres/platforms inline labels use the same `text-muted` token,
      # confirming the visual treatment matches across both surfaces.
      expect(response.body).to include('<td class="text-muted"')
      expect(response.body).to include('<span class="text-muted">genres:')
      expect(response.body).to include('<span class="text-muted">platforms:')
    end

    it "renders `—` placeholder when no genres are linked" do
      game.genres.destroy_all
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">genres:<\/span>\s*—/)
    end

    it "renders `—` placeholder when no platforms are linked" do
      game.platforms_available.destroy_all
      # The canonical-display helper also surfaces Steam/GoG/Epic from
      # the external_* IDs, so clear `external_steam_app_id` (the
      # `:synced` trait stamps one) for this `—` assertion.
      game.update_columns(external_steam_app_id: nil, external_gog_id: nil, external_epic_id: nil)
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">platforms:<\/span>\s*—/)
    end
  end

  # Phase 27 follow-up (2026-05-11) — canonical short-name display.
  # The show page renders the project's locked short labels (PS5,
  # Switch2, Steam, GoG, Epic, Xbox), NOT the verbose IGDB names
  # ("PlayStation 5", "Xbox Series X|S", etc.).
  describe "canonical platform short-names on the show page" do
    let!(:game) { create(:game, :synced, title: "Canonical Test") }

    it "renders 'PS5' instead of 'PlayStation 5'" do
      ps5 = create(:platform, name: "PlayStation 5", igdb_id: 167)
      game.platforms_available << ps5
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">platforms:<\/span>\s*PS5/)
      expect(response.body).not_to include("PlayStation 5</p>")
    end

    it "renders 'Xbox' instead of 'Xbox One' or 'Xbox Series X|S'" do
      xbox_one = create(:platform, name: "Xbox One", igdb_id: 49)
      xsxs     = create(:platform, name: "Xbox Series X|S", igdb_id: 169)
      game.platforms_available << xbox_one
      game.platforms_available << xsxs
      get game_path(game)
      # Collapsed to a single canonical "Xbox" label.
      meta = response.body[/platforms:<\/span>\s*([^<]+)/, 1].to_s.strip
      expect(meta).to eq("Xbox")
    end

    it "drops verbose IGDB names without a canonical alias" do
      ps4 = create(:platform, name: "PlayStation 4", igdb_id: 48)
      pc  = create(:platform, name: "PC (Microsoft Windows)", igdb_id: 6)
      game.platforms_available << ps4
      game.platforms_available << pc
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">platforms:<\/span>\s*—/)
      expect(response.body).not_to include("PlayStation 4")
      expect(response.body).not_to include("PC (Microsoft Windows)")
    end

    it "infers 'Steam' from external_steam_app_id even with no canonical Platform row linked" do
      game.update!(external_steam_app_id: "1234")
      get game_path(game)
      expect(response.body).to match(/<span class="text-muted">platforms:<\/span>\s*Steam/)
    end

    it "renders the full canonical set in locked order" do
      ps5  = create(:platform, name: "PlayStation 5", igdb_id: 167)
      sw2  = create(:platform, name: "Nintendo Switch 2", slug: "switch2", igdb_id: nil)
      xbox = create(:platform, name: "Xbox Series X|S", igdb_id: 169)
      game.platforms_available << ps5
      game.platforms_available << sw2
      game.platforms_available << xbox
      game.update!(
        external_steam_app_id: "1",
        external_gog_id:       "2",
        external_epic_id:      "3"
      )
      get game_path(game)
      meta = response.body[/platforms:<\/span>\s*([^<]+)/, 1].to_s.strip
      expect(meta).to eq("PS5, Switch2, Steam, GoG, Epic, Xbox")
    end
  end
end
