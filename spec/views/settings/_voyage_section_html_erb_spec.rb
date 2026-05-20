require "rails_helper"

# Phase 32 follow-up (2026-05-16) — Voyage section of the Stack pane,
# extracted so `ReindexAllJob` can Turbo-Stream-replace it without
# re-rendering the entire pane. Renders one of two states gated on
# `AppSetting.reindex_running?`:
#
#   * idle    — `[reindex]` destructive bracketed link + confirm modal.
#   * running — `.dot-loader` `=/-` indicator + "reindexing... started
#               ~Xs ago" line.
#
# Both states wrap in a `<div id="voyage_section">` so the broadcast
# target string stays stable.
#
# Beta 4 F3-D — the status surface inside the section is now a
# `Tui::ChipComponent` chip (`[configured]` / `[not configured]`)
# rendered in the sub-panel header via state lookup against
# `Settings::Stack::HealthState::STATES` (FB-82). The previous
# glyph + colored word span is gone.
RSpec.describe "settings/_voyage_section.html.erb", type: :view do
  # Stats payload is read on every render via `Voyage::Stats.call`. Stub
  # it with a minimal shape so the view never touches the DB / Bundle /
  # Game models — these specs are about state-gated affordances, not
  # stats rendering (covered by `Voyage::Stats` + stack pane specs).
  let(:stats_payload) do
    {
      configured: true,
      model: "voyage-3",
      embedded_games_count: 0,
      total_games_count: 0,
      coverage_pct: 0,
      last_indexed_at: nil,
      embedded_bundles_count: nil,
      total_bundles_count: nil,
      bundle_coverage_pct: nil,
      storage_kb: nil,
      embeddings_last_24h: 0
    }
  end

  before do
    allow(Voyage::Stats).to receive(:call).and_return(stats_payload)
  end

  describe "idle state (no reindex running)" do
    before do
      allow(AppSetting).to receive(:reindex_running?).and_return(false)
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      render partial: "settings/voyage_section"
    end

    it "wraps the section in `<div id=\"voyage_section\">` " \
       "(the broadcast target)" do
      expect(rendered).to have_css('div#voyage_section')
    end

    # FB-63-V4 — the `[reindex]` bracketed action no longer lives in
    # the voyage_section partial; it moved up to the parent
    # `_stack_pane.html.erb` and renders inside the sub-panel header
    # via `.pito-sub-panel__actions`. Coverage moved to the stack
    # pane spec. The Voyage section is now purely a stats render.
    it "does NOT render its own `[reindex]` link (moved to parent)" do
      expect(rendered).not_to have_css('a.bracketed.text-danger')
    end

    it "does NOT render the dot-loader indicator" do
      expect(rendered).not_to have_css('.dot-loader')
    end
  end

  describe "running state (reindex in progress)" do
    before do
      allow(AppSetting).to receive(:reindex_running?).and_return(true)
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      allow(AppSetting).to receive(:reindex_started_at)
        .and_return(30.seconds.ago)
      render partial: "settings/voyage_section"
    end

    it "wraps the section in `<div id=\"voyage_section\">`" do
      expect(rendered).to have_css('div#voyage_section')
    end

    it "renders the `.dot-loader` `=/-` indicator" do
      expect(rendered).to have_css('span.dot-loader')
    end

    it "renders the 'reindexing... started ~Xs ago' line via " \
       "compact_time_ago(AppSetting.reindex_started_at)" do
      # i18n template: "reindexing... started %{time_ago}" — the
      # `compact_time_ago(30.seconds.ago)` interpolates as e.g. "30s
      # ago" so both literal "reindexing" and "ago" must appear in the
      # muted span rendered next to the dot loader.
      expect(rendered).to have_css('span.text-muted', text: /reindexing/)
      expect(rendered).to have_text(/reindexing\.\.\. started .*ago/)
    end

    it "does NOT render the `[reindex]` bracketed link" do
      expect(rendered).not_to have_css('a[data-controller="modal-trigger"]')
      expect(rendered).not_to have_css('a.bracketed.text-danger')
    end
  end

  # FB-63-V4 / FB-82 — the Voyage credentials chip (`configured` /
  # `not configured`) is rendered in the parent `_stack_pane.html.erb`
  # sub-panel header via `Settings::Stack::HealthState::STATES`. The
  # voyage_section partial no longer owns that chip. Coverage moved
  # to the stack pane spec.
end
