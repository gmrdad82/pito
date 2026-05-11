require "rails_helper"

# Phase 27 §01c-v2 — Outer Custom collections shelf (nested).
#
# Renders an `<h2>` heading + one sub-shelf per non-empty collection.
# Empty buckets hidden end-to-end (no muted placeholder, no `<h2>`).
RSpec.describe "games/_collections_shelf.html.erb", type: :view do
  def render_shelf(collections)
    render partial: "games/collections_shelf", locals: { collections: collections }
  end

  describe "happy: outer shelf with non-empty collections" do
    let!(:retro)   { create(:collection, name: "Retro") }
    let!(:replay)  { create(:collection, name: "Replay queue") }
    let!(:retro_game)  { create(:game, :synced, title: "Chrono Trigger", collection: retro) }
    let!(:replay_game) { create(:game, :synced, title: "Hollow Knight",  collection: replay) }

    it "renders the outer-shelf <section> with the outer-collections data hook" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).to include('data-shelf="outer-collections"')
      expect(rendered).to match(%r{<section[^>]*shelf--collections outer-shelf})
    end

    it "renders one <h2> labelled 'custom collections'" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).to match(%r{<h2[^>]*>\s*custom collections\s*</h2>})
    end

    it "renders one sub-shelf per collection" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered.scan('data-shelf="collection-sub"').length).to eq(2)
    end

    it "renders the collection name in each sub-shelf <h3>" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).to match(%r{<h3[^>]*>\s*Retro\s*</h3>})
      expect(rendered).to match(%r{<h3[^>]*>\s*Replay queue\s*</h3>})
    end
  end

  describe "edge: empty input" do
    it "renders NOTHING when no collections are provided" do
      render_shelf(Collection.none)
      expect(rendered.strip).to eq("")
    end

    it "does NOT render the legacy '(no collections yet)' placeholder" do
      render_shelf(Collection.none)
      expect(rendered).not_to include("(no collections yet)")
    end

    it "does NOT render an <h2> when input is empty" do
      render_shelf(Collection.none)
      expect(rendered).not_to match(%r{<h2[^>]*>\s*custom collections\s*</h2>})
    end

    it "does NOT render an outer-shelf <section> when input is empty" do
      render_shelf(Collection.none)
      expect(rendered).not_to include('data-shelf="outer-collections"')
    end
  end

  describe "flaw: no v1 flat-tile remnants" do
    let!(:retro)      { create(:collection, name: "Retro") }
    let!(:retro_game) { create(:game, :synced, title: "EarthBound", collection: retro) }

    it "does NOT render `.tile tile--shelf` anchors (v1 collection-name tile)" do
      render_shelf(Collection.where(id: retro.id))
      expect(rendered).not_to include('class="tile tile--shelf"')
    end

    it "does NOT render the v1 `[<name>]` bracketed legend in a tile cover block" do
      render_shelf(Collection.where(id: retro.id))
      # v1 emitted `[retro]` inside a `tile-cover` block. v2 puts a
      # leading composite cover tile + game tiles instead.
      expect(rendered).not_to match(%r{<span class="text-muted"[^>]*>\s*\[retro\]\s*</span>})
    end
  end
end
