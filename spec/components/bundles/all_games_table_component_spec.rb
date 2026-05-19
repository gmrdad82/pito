require "rails_helper"

# Bundles::AllGamesTableComponent — flat `.sessions-table`-styled
# listing of every game in a bundle, rendered inside the bundle modal
# below the composite cover grid. Replaces the prior `+N more`
# overflow shelf. Columns: checkbox, title, primary genre, release
# date, rating score chip.
#
# Stubbed games + association: we lean on `build_stubbed` and
# `allow(bundle).to receive(:games)` to avoid DB writes. The component
# calls `bundle.games.includes(:primary_genre).reorder(:title)` so we
# return a chainable double whose `.includes(...).reorder(...)`
# resolves to the prepared in-memory list. `.reorder` (not `.order`)
# matters because `bundle_members` carries a default `order(:position)`
# scope that propagates through the `has_many :through`; the table
# wants alphabetical, so it must REPLACE the default order, not append.
RSpec.describe Bundles::AllGamesTableComponent, type: :component do
  # The component's html template renders the sibling
  # `shared/_omnisearch_modal` partial which calls
  # `Bundles::Recommender.call(bundle, limit:)`. We stub the
  # recommender to return an empty relation-ish for every example;
  # the recommender's own behavior has its own spec coverage.
  before do
    allow(Bundles::Recommender).to receive(:call).and_return([])
  end

  # Wraps a plain array of games so the component's
  # `.includes(:primary_genre).reorder(:title)` chain works without a
  # DB hit. `reorder(:title)` is applied in Ruby so we honor the
  # contract.
  def stub_bundle_with(games)
    bundle = build_stubbed(:bundle)
    relation = double("games-relation")
    allow(relation).to receive(:includes).with(:primary_genre).and_return(relation)
    allow(relation).to receive(:reorder).with(:title) do
      games.sort_by { |g| g.title.to_s }
    end
    allow(bundle).to receive(:games).and_return(relation)
    bundle
  end

  def stub_empty_bundle
    stub_bundle_with([])
  end

  describe "#primary_genre_label" do
    let(:bundle) { stub_empty_bundle }
    let(:component) { described_class.new(bundle: bundle) }

    it "returns the genre display name when a primary genre is set" do
      genre = build_stubbed(:genre, name: "Adventure")
      game = build_stubbed(:game, primary_genre: genre)
      expect(component.primary_genre_label(game)).to eq("Adventure")
    end

    it "applies GENRE_DISPLAY_RENAMES (Role-playing (RPG) -> RPG)" do
      genre = build_stubbed(:genre, name: "Role-playing (RPG)")
      game = build_stubbed(:game, primary_genre: genre)
      expect(component.primary_genre_label(game)).to eq("RPG")
    end

    it "falls back to the em-dash when primary_genre is nil" do
      game = build_stubbed(:game, primary_genre: nil)
      expect(component.primary_genre_label(game)).to eq(I18n.t("common.em_dash"))
    end

    it "falls back to the em-dash when the genre name is blank" do
      genre = build_stubbed(:genre, name: "")
      game = build_stubbed(:game, primary_genre: genre)
      expect(component.primary_genre_label(game)).to eq(I18n.t("common.em_dash"))
    end
  end

  describe "#short_release_date" do
    let(:bundle) { stub_empty_bundle }
    let(:component) { described_class.new(bundle: bundle) }

    it "formats a present release_date as m-d-Y" do
      game = build_stubbed(:game, release_date: Date.new(2024, 1, 15))
      expect(component.short_release_date(game)).to eq("01-15-2024")
    end

    it "returns the em-dash when release_date is nil" do
      game = build_stubbed(:game, release_date: nil)
      expect(component.short_release_date(game)).to eq(I18n.t("common.em_dash"))
    end
  end

  describe "#omnisearch_dialog_id / #omnisearch_frame_id" do
    it "scopes the dialog id by bundle id" do
      bundle = build_stubbed(:bundle, id: 4242)
      allow(bundle).to receive(:games).and_return(
        double(includes: double(reorder: []))
      )
      component = described_class.new(bundle: bundle)
      expect(component.omnisearch_dialog_id).to eq("omnisearch-modal-bundle-4242")
    end

    it "uses a fixed frame id shared by the bundle_add mode" do
      bundle = build_stubbed(:bundle, id: 7)
      allow(bundle).to receive(:games).and_return(
        double(includes: double(reorder: []))
      )
      component = described_class.new(bundle: bundle)
      expect(component.omnisearch_frame_id).to eq("omnisearch_results_bundle_add")
    end

    it "produces distinct dialog ids for different bundles" do
      a = build_stubbed(:bundle, id: 1)
      b = build_stubbed(:bundle, id: 2)
      [ a, b ].each do |bun|
        allow(bun).to receive(:games).and_return(
          double(includes: double(reorder: []))
        )
      end
      id_a = described_class.new(bundle: a).omnisearch_dialog_id
      id_b = described_class.new(bundle: b).omnisearch_dialog_id
      expect(id_a).not_to eq(id_b)
    end
  end

  describe "rendering: heading + chrome" do
    it "renders the localized heading copy" do
      render_inline(described_class.new(bundle: stub_empty_bundle))
      expect(page).to have_css("section.all-games h3", text: I18n.t("bundles.all_games.heading"))
    end

    it "renders the [+] add-member trigger wired to the omnisearch dialog id" do
      bundle = stub_empty_bundle
      allow(bundle).to receive(:id).and_return(99)
      render_inline(described_class.new(bundle: bundle))
      trigger = page.find('a[data-controller="modal-trigger"]')
      expect(trigger["data-modal-trigger-target-id-value"]).to eq("omnisearch-modal-bundle-99")
      expect(trigger["data-action"]).to eq("click->modal-trigger#open")
    end

    it "renders a sortable .sessions-table.all-games-table" do
      render_inline(described_class.new(bundle: stub_empty_bundle))
      expect(page).to have_css("table.sessions-table.all-games-table", count: 1)
      expect(page).to have_css('[data-controller="sortable-table"]', count: 1)
      expect(page).to have_css('[data-sortable-table-no-url-value="yes"]', count: 1)
    end

    it "renders all five column headers (checkbox + title + genre + release + score)" do
      render_inline(described_class.new(bundle: stub_empty_bundle))
      # checkbox column is unsortable; the other four come through
      # SortableHeaderComponent and carry their label text.
      expect(page).to have_css("thead th", count: 5)
      expect(page).to have_css("th.all-games-col-check", count: 1)
      expect(page).to have_css("th.all-games-col-title", text: I18n.t("bundles.all_games.col.title"))
      expect(page).to have_css("th.all-games-col-genre", text: I18n.t("bundles.all_games.col.genre"))
      expect(page).to have_css("th.all-games-col-release", text: I18n.t("bundles.all_games.col.release"))
      expect(page).to have_css("th.all-games-col-score", text: I18n.t("bundles.all_games.col.score"))
    end
  end

  describe "rendering: empty bundle" do
    it "renders the empty-state row when the bundle has no games" do
      render_inline(described_class.new(bundle: stub_empty_bundle))
      expect(page).to have_css('tbody td[colspan="5"]', text: I18n.t("bundles.all_games.empty"))
    end

    it "renders zero body data rows when the bundle is empty" do
      render_inline(described_class.new(bundle: stub_empty_bundle))
      expect(page).to have_no_css("tbody tr td.all-games-col-title")
    end
  end

  describe "rendering: single-game bundle" do
    let(:game) do
      build_stubbed(
        :game,
        title: "Halo Infinite",
        release_date: Date.new(2021, 12, 8),
        primary_genre: build_stubbed(:genre, name: "Shooter")
      )
    end
    let(:bundle) { stub_bundle_with([ game ]) }

    it "renders exactly one data row" do
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css("tbody tr", count: 1)
    end

    it "renders the title as a link to /games/:id escaping the Turbo Frame" do
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css(
        "td.all-games-col-title a[data-turbo-frame='_top']",
        text: "Halo Infinite"
      )
      expect(page.find("td.all-games-col-title a")[:href]).to eq("/games/#{game.id}")
    end

    it "uses the game title as the title attribute on the title cell" do
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css('td.all-games-col-title[title="Halo Infinite"]')
    end

    it "renders the primary genre display label in the genre cell" do
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css("td.all-games-col-genre", text: "Shooter")
    end

    it "renders the release date in m-d-Y form with an ISO data-sort-value" do
      render_inline(described_class.new(bundle: bundle))
      cell = page.find("td.all-games-col-release")
      expect(cell.text.strip).to eq("12-08-2021")
      expect(cell["data-sort-value"]).to eq("2021-12-08")
    end

    it "renders a per-row checkbox carrying name=game_ids[] and the game id as value" do
      render_inline(described_class.new(bundle: bundle))
      checkbox = page.find('tbody input[type="checkbox"]')
      expect(checkbox["name"]).to eq("game_ids[]")
      expect(checkbox["value"]).to eq(game.id.to_s)
    end
  end

  describe "rendering: multi-game bundle, ordered by title" do
    let(:zelda) do
      build_stubbed(:game, title: "Zelda", release_date: Date.new(2023, 5, 12))
    end
    let(:bayonetta) do
      build_stubbed(:game, title: "Bayonetta", release_date: nil)
    end
    let(:mario) do
      build_stubbed(:game, title: "Mario", release_date: Date.new(2017, 10, 27))
    end
    let(:bundle) { stub_bundle_with([ zelda, bayonetta, mario ]) }

    it "renders one row per game" do
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css("tbody tr", count: 3)
    end

    it "orders the rows alphabetically by title (Bayonetta, Mario, Zelda)" do
      render_inline(described_class.new(bundle: bundle))
      titles = page.all("tbody td.all-games-col-title a").map(&:text)
      expect(titles).to eq([ "Bayonetta", "Mario", "Zelda" ])
    end

    it "renders the em-dash for the row with a nil release_date" do
      render_inline(described_class.new(bundle: bundle))
      release_cells = page.all("tbody td.all-games-col-release").map { |c| c.text.strip }
      expect(release_cells).to include(I18n.t("common.em_dash"))
    end

    it "renders the em-dash in the genre column for games with no primary_genre" do
      render_inline(described_class.new(bundle: bundle))
      genre_texts = page.all("tbody td.all-games-col-genre").map { |c| c.text.strip }
      expect(genre_texts.uniq).to eq([ I18n.t("common.em_dash") ])
    end
  end

  describe "rendering: rating score chip integration" do
    it "renders the .rating-score-chip element for a game with a synthesized score" do
      rated = build_stubbed(
        :game,
        title: "Rated",
        igdb_rating: 88.0,
        igdb_rating_count: 100,
        aggregated_rating: nil,
        aggregated_rating_count: nil,
        total_rating: nil,
        total_rating_count: nil
      )
      render_inline(described_class.new(bundle: stub_bundle_with([ rated ])))
      expect(page).to have_css("td.all-games-col-score span.rating-score-chip", count: 1)
      expect(page.find("td.all-games-col-score")["data-sort-value"]).to eq("88")
    end

    it "stamps the chip's tier from the synthesized score (88 -> good)" do
      rated = build_stubbed(
        :game,
        igdb_rating: 88.0,
        igdb_rating_count: 100,
        aggregated_rating: nil,
        aggregated_rating_count: nil,
        total_rating: nil,
        total_rating_count: nil
      )
      render_inline(described_class.new(bundle: stub_bundle_with([ rated ])))
      expect(page).to have_css('span.rating-score-chip[data-tier="good"]')
    end

    it "renders no chip element when the game has no synthesized score, and uses -1 as the sort value" do
      unrated = build_stubbed(
        :game,
        igdb_rating: nil,
        igdb_rating_count: 0,
        aggregated_rating: nil,
        aggregated_rating_count: 0,
        total_rating: nil,
        total_rating_count: 0
      )
      render_inline(described_class.new(bundle: stub_bundle_with([ unrated ])))
      expect(page).to have_no_css("span.rating-score-chip")
      cell = page.find("td.all-games-col-score")
      expect(cell["data-sort-value"]).to eq("-1")
    end

    it "delegates to Games::RatingScoreChipComponent (constructed with the row's game)" do
      game = build_stubbed(:game, title: "Anything")
      bundle = stub_bundle_with([ game ])

      chip = Games::RatingScoreChipComponent.new(game: game)
      expect(Games::RatingScoreChipComponent).to receive(:new).with(game: game).and_return(chip)

      render_inline(described_class.new(bundle: bundle))
    end
  end
end
