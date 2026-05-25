require "rails_helper"

RSpec.describe Pito::GamesReleasing::ShelfTileComponent, type: :component do
  let(:game) do
    g = Game.new(
      title:        "Hollow Knight: Silksong",
      igdb_slug:    "hollow-knight-silksong-test",
      release_date: Date.current + 12.days,
      release_year: (Date.current + 12.days).year
    )
    g.save!(validate: false)
    g
  end

  subject(:rendered) { render_inline(described_class.new(game: game)) }
  let(:root) { rendered.css(".upcoming-tile").first }

  it "renders the upcoming-tile anchor wrapper" do
    expect(root).to be_present
    expect(root.name).to eq("a")
    expect(root["title"]).to eq(game.title)
  end

  it "links to the game's show route" do
    expect(root["href"]).to include(game.igdb_slug)
  end

  it "uses data-turbo-frame=_top so a click escapes any surrounding frame" do
    expect(root["data-turbo-frame"]).to eq("_top")
  end

  it "carries a per-game focusable key (upcoming_<id>)" do
    expect(root["data-tui-focusable"]).to eq("upcoming_#{game.id}")
  end

  describe "cover" do
    it "renders the Game::CoverComponent in :shelf_fill variant" do
      cover = rendered.css(".upcoming-tile__cover-wrap [data-variant='shelf_fill']").first
      expect(cover).to be_present
    end

    it "does NOT wrap the cover in its own anchor (the tile is already linked)" do
      cover_anchors = rendered.css(".upcoming-tile__cover-wrap a[data-variant]")
      expect(cover_anchors).to be_empty
    end
  end

  describe "title" do
    it "renders the title text" do
      title_el = rendered.css(".upcoming-tile__title").first
      expect(title_el).to be_present
      expect(title_el.text.strip).to eq(game.title)
    end
  end

  describe "time-until-release" do
    it "renders an 'in Nd' / 'in Nw' compact string" do
      when_el = rendered.css(".upcoming-tile__when").first
      expect(when_el).to be_present
      # 12 days out → 'in 1w' (12 / 7 floor = 1)
      expect(when_el.text.strip).to eq("in 1w")
    end

    it "suppresses the time-until-release row when release_date is nil" do
      game.update_columns(release_date: nil)
      rerendered = render_inline(described_class.new(game: game.reload))
      expect(rerendered.css(".upcoming-tile__when")).to be_empty
    end
  end
end
