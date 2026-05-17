require "rails_helper"

# Phase 27 v2 spec 03 — sync-status partial. Rendered inside the
# show page's Row 2 pane AND broadcast by `GameIgdbSync` over the
# `"game_resync:<id>"` Turbo-Stream when a resync starts / finishes.
# The wrapper id (`game_sync_status_<id>`) is the Turbo replace
# target.
RSpec.describe "games/_sync_status.html.erb", type: :view do
  let(:game) { create(:game, :synced) }

  it "renders the wrapper div keyed on the game id" do
    render partial: "games/sync_status", locals: { game: game }
    expect(rendered).to include(%(id="game_sync_status_#{game.id}"))
  end

  context "when game.resyncing? is true" do
    before { game.update_column(:resyncing, true) }

    it "renders the dot-loader sync-indicator span" do
      render partial: "games/sync_status", locals: { game: game }
      expect(rendered).to include('data-controller="sync-indicator"')
      expect(rendered).to include('data-sync-indicator-frames-value=')
    end

    it "does NOT render the [resync] button" do
      render partial: "games/sync_status", locals: { game: game }
      expect(rendered).not_to match(/<span class="bl">resync<\/span>/)
    end
  end

  context "when game.resyncing? is false" do
    before { game.update_column(:resyncing, false) }

    it "renders the [resync] button when igdb_id is present" do
      render partial: "games/sync_status", locals: { game: game }
      expect(rendered).to include('<span class="bl">resync</span>')
    end

    it "does NOT render the sync-indicator" do
      render partial: "games/sync_status", locals: { game: game }
      expect(rendered).not_to include('data-controller="sync-indicator"')
    end

    it "renders the relative `synced X ago.` label when igdb_synced_at is set" do
      game.update_column(:igdb_synced_at, 22.minutes.ago)
      render partial: "games/sync_status", locals: { game: game }
      expect(rendered).to match(/synced .+ ago\./)
    end

    it "renders the `not synced yet.` label when igdb_synced_at is nil" do
      game.update_column(:igdb_synced_at, nil)
      render partial: "games/sync_status", locals: { game: game }
      expect(rendered).to include("not synced yet.")
    end

    it "renders the post-sync caveat (one sentence per line)" do
      render partial: "games/sync_status", locals: { game: game }
      expect(rendered).to include("re-syncing overwrites igdb-sourced fields.")
      expect(rendered).to include("local notes, played-on, footage hours, and platform-owned survive.")
    end
  end

  context "when igdb_id is blank (a local-only game)" do
    let(:local_game) do
      g = create(:game, title: "Local-only", igdb_id: nil)
      g.update_columns(resyncing: false, igdb_synced_at: nil)
      g.reload
    end

    it "does NOT render the [resync] button (no IGDB id to resync against)" do
      render partial: "games/sync_status", locals: { game: local_game }
      expect(rendered).not_to include('<span class="bl">resync</span>')
    end

    it "renders the `not synced yet.` label" do
      render partial: "games/sync_status", locals: { game: local_game }
      expect(rendered).to include("not synced yet.")
    end
  end
end
