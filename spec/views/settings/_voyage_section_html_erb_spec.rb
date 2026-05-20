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
# rendered by `Settings::Stack::HealthLineComponent`. The previous
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

    it "renders the `[reindex]` destructive bracketed link wired to " \
       "the confirm modal" do
      # BracketedLinkComponent emits `class="bracketed text-danger"` on
      # the anchor and the label is wrapped in `[<span class="bl">…]`.
      # `data-controller="modal-trigger"` + `modal_trigger_target_id_value`
      # are the wiring to the confirm modal mounted in `_stack_pane`.
      expect(rendered).to have_css(
        'a.bracketed.text-danger[data-controller="modal-trigger"]' \
        '[data-modal-trigger-target-id-value="reindex_meilisearch_modal"]',
        text: /reindex/
      )
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

  # Beta 4 F3-D — the Voyage credentials state is rendered by
  # `Settings::Stack::HealthLineComponent`, which now delegates to
  # `Tui::ChipComponent`. The chip's variant carries the operator
  # signal (`:info` for configured, `:danger` for not configured).
  describe "Voyage credentials gating" do
    before do
      allow(AppSetting).to receive(:reindex_running?).and_return(false)
    end

    it "shows a `Tui::ChipComponent` `[configured]` chip with the info " \
       "variant when AppSetting.voyage_configured? is true" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      render partial: "settings/voyage_section"

      expect(rendered).to have_css(
        "span.tui-chip.tui-chip--info", text: "[configured]"
      )
      expect(rendered).not_to have_css(
        "span.tui-chip.tui-chip--danger", text: "[not configured]"
      )
    end

    it "shows a `Tui::ChipComponent` `[not configured]` chip with the " \
       "danger variant when AppSetting.voyage_configured? is false" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      render partial: "settings/voyage_section"

      expect(rendered).to have_css(
        "span.tui-chip.tui-chip--danger", text: "[not configured]"
      )
      expect(rendered).not_to have_css(
        "span.tui-chip.tui-chip--info", text: "[configured]"
      )
    end
  end
end
