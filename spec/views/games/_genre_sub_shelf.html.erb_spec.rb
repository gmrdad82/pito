require "rails_helper"

# Phase 27 §01c-v2 — Genre sub-shelf row.
#
# Single sub-shelf per genre. `<h3>` heading + optional `[see all]`
# link + horizontal scrolling row of game tiles at the `:shelf` cover
# variant. Cap 30, alphabetical by `LOWER(games.title)`.
RSpec.describe "games/_genre_sub_shelf.html.erb", type: :view do
  def render_partial(genre)
    render partial: "games/genre_sub_shelf", locals: { genre: genre }
  end

  let!(:genre) { create(:genre, name: "Adventure", igdb_id: 9_201, slug: "adventure") }

  describe "happy: genre with a small game list (under cap)" do
    let!(:zelda) { create(:game, :synced, title: "Zelda BotW",  cover_image_id: "img-zelda") }
    let!(:tunic) { create(:game, :synced, title: "Tunic",       cover_image_id: "img-tunic") }
    let!(:abzu)  { create(:game, :synced, title: "ABZU",        cover_image_id: "img-abzu") }

    before do
      [ zelda, tunic, abzu ].each { |g| g.genres << genre }
    end

    it "renders an <h3> with the genre's short-form name" do
      render_partial(genre)
      expect(rendered).to match(%r{<h3[^>]*>\s*Adventure\s*</h3>})
    end

    it "renders one shelf-variant cover tile per game" do
      render_partial(genre)
      expect(rendered.scan('game-cover--shelf').length).to eq(3)
    end

    it "orders games alphabetical case-insensitive by title" do
      render_partial(genre)
      indexes = [ "ABZU", "Tunic", "Zelda BotW" ].map { |t| rendered.index(t) }
      expect(indexes).to eq(indexes.compact.sort)
    end

    it "does NOT render a `[see all]` link when under the cap" do
      render_partial(genre)
      expect(rendered).not_to include(">see all<")
    end

    it "stamps the steam-shelf Stimulus controller on the sub-shelf wrapper" do
      render_partial(genre)
      expect(rendered).to include('data-controller="steam-shelf"')
      expect(rendered).to include('data-shelf="genre-sub"')
    end

    it "stamps data-genre-id on the sub-shelf wrapper" do
      render_partial(genre)
      expect(rendered).to include(%(data-genre-id="#{genre.id}"))
    end
  end

  describe "edge: genre with exactly the cap (30 games)" do
    before do
      30.times do |i|
        # Sequence titles "0001 game" … "0030 game" so alphabetical
        # ordering is trivially predictable.
        g = create(:game, :synced, title: format("%04d game", i + 1))
        g.genres << genre
      end
    end

    it "renders all 30 tiles" do
      render_partial(genre)
      expect(rendered.scan('game-cover--shelf').length).to eq(30)
    end

    it "does NOT render `[see all]` at exactly the cap" do
      render_partial(genre)
      expect(rendered).not_to include(">see all<")
    end
  end

  describe "edge: genre with more than the cap (31 games → 30 + see all)" do
    before do
      31.times do |i|
        g = create(:game, :synced, title: format("%04d game", i + 1))
        g.genres << genre
      end
    end

    it "renders exactly 30 tiles (capped)" do
      render_partial(genre)
      expect(rendered.scan('game-cover--shelf').length).to eq(30)
    end

    it "renders a `[see all]` bracketed link when over the cap" do
      render_partial(genre)
      expect(rendered).to include(">see all<")
    end

    it "`[see all]` href targets /games?genre=<slug> when slug present" do
      render_partial(genre)
      expect(rendered).to include(%(href="#{games_path(genre: "adventure")}"))
    end

    it "`[see all]` href falls back to /games?genre=<id> when slug is blank" do
      genre.update_column(:slug, nil)
      render_partial(genre.reload)
      expect(rendered).to include(%(href="#{games_path(genre: genre.id)}"))
    end
  end

  describe "edge: genre with zero games" do
    it "renders the <h3> heading but no tiles" do
      render_partial(genre)
      expect(rendered).to match(%r{<h3[^>]*>\s*Adventure\s*</h3>})
      expect(rendered).not_to include('game-cover--shelf')
    end

    it "does NOT render `[see all]` when count is zero" do
      render_partial(genre)
      expect(rendered).not_to include(">see all<")
    end
  end

  describe "flaw: no JS confirm / alert affordances" do
    let!(:zelda) { create(:game, :synced, title: "Zelda BotW") }

    before { zelda.genres << genre }

    it "does NOT include data-turbo-confirm anywhere in the sub-shelf" do
      render_partial(genre)
      expect(rendered).not_to include("data-turbo-confirm")
    end

    it "does NOT include a <script> tag" do
      render_partial(genre)
      expect(rendered).not_to include("<script")
    end
  end
end
