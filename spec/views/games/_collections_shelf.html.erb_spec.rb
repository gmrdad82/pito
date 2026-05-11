require "rails_helper"

# Phase 27 follow-up (2026-05-11) — Collections outer shelf.
#
# Single-row layout: one tile per collection, click opens a modal
# with the collection's games via Turbo Frame. Replaces the prior
# nested sub-shelf-per-collection design.
RSpec.describe "games/_collections_shelf.html.erb", type: :view do
  def render_shelf(collections)
    render partial: "games/collections_shelf", locals: { collections: collections }
  end

  describe "happy: outer shelf with non-empty collections" do
    let!(:retro)       { create(:collection, name: "Retro") }
    let!(:replay)      { create(:collection, name: "Replay queue") }
    let!(:retro_game)  { create(:game, :synced, title: "Chrono Trigger", collection: retro) }
    let!(:replay_game) { create(:game, :synced, title: "Hollow Knight",  collection: replay) }

    it "renders the outer-shelf <section> with the outer-collections data hook" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).to include('data-shelf="outer-collections"')
      expect(rendered).to match(%r{<section[^>]*shelf--collections outer-shelf})
    end

    it "renders one <h2> labelled 'collections'" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).to match(%r{<h2[^>]*>\s*collections\s*</h2>})
      expect(rendered).not_to match(%r{<h2[^>]*>\s*custom collections\s*</h2>})
    end

    it "renders one collection-tile per collection (NOT one sub-shelf each)" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered.scan(%r{class="collection-tile"}).length).to eq(2)
    end

    it "does NOT render the legacy per-collection sub-shelves" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).not_to include('data-shelf="collection-sub"')
    end

    it "renders the collection name in each tile" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).to include("Retro")
      expect(rendered).to include("Replay queue")
    end

    it "wires each tile to the collections-modal-trigger Stimulus controller" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered.scan('data-controller="collections-modal-trigger"').length).to eq(2)
      expect(rendered).to include('data-action="click->collections-modal-trigger#open"')
    end

    it "points each tile's `url` value at /collections/<slug>/games_pane" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).to include("/collections/#{retro.slug}/games_pane")
      expect(rendered).to include("/collections/#{replay.slug}/games_pane")
    end

    it "emits the layout-level <dialog id=\"collections-modal\"> alongside the shelf" do
      render_shelf(Collection.where(id: [ retro.id, replay.id ]))
      expect(rendered).to include('id="collections-modal"')
      expect(rendered).to include('id="collections_modal_frame"')
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
      expect(rendered).not_to match(%r{<h2[^>]*>\s*collections\s*</h2>})
    end

    it "does NOT render the dialog when input is empty" do
      render_shelf(Collection.none)
      expect(rendered).not_to include('id="collections-modal"')
    end
  end

  describe "edge: collection with no composite cover yet (composer returned nil)" do
    let!(:lone) { create(:collection, name: "Lone game") }
    let!(:lone_game) { create(:game, :synced, title: "Solo", collection: lone) }

    it "renders the shelf-variant fallback SVG (light + dark) for the tile cover" do
      render_shelf(Collection.where(id: lone.id))
      expect(rendered).to include("game_cover_fallback_shelf_light")
      expect(rendered).to include("game_cover_fallback_shelf_dark")
    end
  end

  describe "happy: collection with composite cover already stamped" do
    let!(:stamped) do
      collection = create(:collection, name: "Two-game")
      create(:game, :synced, title: "Game A", collection: collection)
      create(:game, :synced, title: "Game B", collection: collection)
      collection.update_columns(
        composite_cover_path:     "composites/collection-#{collection.id}.jpg",
        composite_cover_checksum: "deadbeef"
      )
      collection
    end

    it "renders the composite cover <img> with the fingerprint cache-buster" do
      render_shelf(Collection.where(id: stamped.id))
      expect(rendered).to include("/composites/collection-#{stamped.id}.jpg?v=deadbeef")
      expect(rendered).to include('class="collection-cover-composite"')
    end
  end

  describe "flaw: no legacy structures leak through" do
    let!(:retro)      { create(:collection, name: "Retro") }
    let!(:retro_game) { create(:game, :synced, title: "EarthBound", collection: retro) }

    it "does NOT render the v2 `data-shelf=\"collection-sub\"` sub-shelf" do
      render_shelf(Collection.where(id: retro.id))
      expect(rendered).not_to include('data-shelf="collection-sub"')
    end

    it "does NOT render the v1 `[<name>]` bracketed legend tile" do
      render_shelf(Collection.where(id: retro.id))
      expect(rendered).not_to match(%r{<span class="text-muted"[^>]*>\s*\[retro\]\s*</span>})
    end
  end
end
