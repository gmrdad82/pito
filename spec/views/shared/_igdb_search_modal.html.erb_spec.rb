require "rails_helper"

# Phase 27 spec 04 (2026-05-17) — global IGDB add-game modal polish.
# Covers the copy + control changes pinned by the spec: trimmed title,
# trimmed input placeholder, no `[search]` button, bracketed-muted
# `[cancel]` rendered via `BracketedMutedLinkComponent`, the
# `.pane-dialog--wide` modifier (replacing the inline max-width hack),
# the auto-search Stimulus value, and the dual `input` + `keydown.enter`
# action wiring on the input target.
RSpec.describe "shared/_igdb_search_modal.html.erb", type: :view do
  def render_modal
    render partial: "shared/igdb_search_modal"
  end

  describe "copy" do
    it "renders the dialog title as 'add a game'" do
      render_modal
      expect(rendered).to include(">add a game<")
    end

    it "does NOT include the legacy 'add a game from igdb' copy" do
      render_modal
      expect(rendered).not_to include("add a game from igdb")
    end

    it "renders the input placeholder as 'search…'" do
      render_modal
      expect(rendered).to match(/placeholder="search[^"]*"/)
      expect(rendered).not_to include('placeholder="search igdb…"')
    end
  end

  describe "controls" do
    it "does NOT render a [search] button" do
      render_modal
      expect(rendered).not_to match(/<button[^>]*>\[<span class="bl">search<\/span>\]/)
      expect(rendered).not_to include('data-action="igdb-search-modal#submit"')
    end

    it "renders exactly one bracketed-muted [cancel] link in the footer" do
      render_modal
      # Footer carries one control — the muted [cancel] link.
      expect(rendered.scan(/bracketed-muted-link/).length).to eq(1)
      expect(rendered).to match(
        /class="bracketed bracketed-muted-link"[^>]*>\[<span class="bl">cancel<\/span>\]/
      )
    end

    it "wires [cancel] to the #close action" do
      render_modal
      expect(rendered).to include('data-action="click-&gt;igdb-search-modal#close"')
        .or include('data-action="click->igdb-search-modal#close"')
    end
  end

  describe "auto-search wiring" do
    it "wires the input to both #search (input event) and Enter" do
      render_modal
      expect(rendered).to include('data-action="input->igdb-search-modal#search keydown.enter->igdb-search-modal#search"')
    end

    it "exposes the min-chars value on the dialog" do
      render_modal
      expect(rendered).to include('data-igdb-search-modal-min-chars-value="5"')
    end
  end

  describe "dialog sizing" do
    it "opts into the .pane-dialog--wide modifier (no inline max-width hack)" do
      render_modal
      expect(rendered).to include("pane-dialog--wide")
      expect(rendered).not_to match(/style="[^"]*max-width:\s*720px/)
    end
  end

  describe "CLAUDE.md hard rules" do
    it "carries no data-turbo-confirm anywhere" do
      render_modal
      expect(rendered).not_to include("data-turbo-confirm")
    end

    it "carries no inline JS confirm/alert/prompt" do
      render_modal
      expect(rendered).not_to match(/window\.(confirm|alert|prompt)/)
    end
  end
end
