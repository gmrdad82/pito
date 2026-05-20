require "rails_helper"

# Phase 29 (settings refactor) — stack pane partial (row 3, wide).
# Beta 4 F3-D restructured the inner layout from a 2-column-with-
# divider into a 3x2 tile grid. Each subsystem (Postgres / Meilisearch
# / Redis / Voyage AI / assets / notes) lives in its own tile with a
# `Tui::ChipComponent` status indicator + hairline borders to neighbor
# tiles. Metrics use `.num` (font-variant-numeric: tabular-nums via
# the existing global rule).
RSpec.describe "settings/_stack_pane.html.erb", type: :view do
  before do
    assign(:postgres_status, { connected: true, adapter: "postgresql", database: "pito_test", version: "17" })
    assign(:redis_status, { connected: true, version: "7", used_memory_human: "1MB", db_size: 0, persistence: "rdb" })
    assign(:search_healthy, true)
    assign(:search_per_index_stats, [])
    assign(:postgres_table_breakdown, [
      { label: "channels", count: 1, size_bytes: 4096 },
      { label: "videos", count: 0, size_bytes: 0 }
    ])
    assign(:sidekiq_breakdown, [
      { label: "processed", count: 0 },
      { label: "failed", count: 0 },
      { label: "busy", count: 0 },
      { label: "scheduled", count: 0 },
      { label: "enqueued", count: 0 },
      { label: "retry", count: 0 },
      { label: "dead", count: 0 }
    ])
    assign(:storage_status, { path: "/tmp", present: true, writable: true, size_bytes: 0, file_count: 0 })
    assign(:notes_volume_status, { present: true, writable: true, size_bytes: 0, file_count: 0 })
    assign(:assets_breakdown, [])
    assign(:notes_breakdown, [])
    assign(:voyage_configured, false)
    render partial: "settings/stack_pane"
  end

  it "renders the stack heading inside a wide pane" do
    expect(rendered).to include('<span class="pito-pane__title">stack</span>')
    expect(rendered).to include("pane--wide")
  end

  it "renders all six surface labels" do
    # All six stack surfaces still render: PostgreSQL + Redis +
    # Meilisearch + Voyage AI (top two rows) + assets + notes
    # (bottom row). The brand-name capitalization mirrors the
    # i18n keys (`Postgres`, `Redis`, `Meilisearch`, `Voyage AI`)
    # and the lowercase section names (`assets`, `notes`).
    expect(rendered).to include("Postgres")
    expect(rendered).to include("Redis")
    expect(rendered).to include("Meilisearch")
    expect(rendered).to include("Voyage AI")
    expect(rendered).to include("assets")
    expect(rendered).to include("notes")
  end

  it "lays out the inner pane as a vertical flex column via `.stack-pane-grid`" do
    # FB-51/FB-52 V4 — the legacy `1fr 1fr` 2-col tile grid has been
    # dropped in favor of a vertical flex column. The flex layout is
    # carried by the `.stack-pane-grid` CSS class (no inline grid
    # styles). No `.stack-pane-divider` element, no per-tile
    # `border-right`.
    expect(rendered).to include('class="stack-pane-grid"')
    expect(rendered).not_to include("grid-template-columns: 1fr 1fr")
    expect(rendered).not_to include('class="stack-pane-divider"')
  end

  it "renders a Tui::ChipComponent status chip for each of the six subsystems" do
    # Each sub-panel header resolves its semantic state via
    # `Settings::Stack::HealthState::STATES` and renders a
    # `Tui::ChipComponent` (`span.tui-chip`) with the matching variant
    # modifier. Six chips total (one per tile): PostgreSQL,
    # Meilisearch, Redis, Voyage AI, assets, notes.
    expect(rendered).to have_css("span.tui-chip", count: 6)
  end

  it "uses the success chip variant for the connected Postgres status" do
    # FB-CHIP-V2-IMPL — V2 chips render bare label, no brackets.
    expect(rendered).to have_css(
      "span.tui-chip.tui-chip--success", text: "connected"
    )
  end

  it "uses the success chip variant for the writable assets status" do
    # FB-6 — chip colors collapsed to 2 (success=green, danger=pink);
    # `writable` is a healthy state, so it resolves to `success`.
    expect(rendered).to have_css(
      "span.tui-chip.tui-chip--success", text: "writable"
    )
  end

  it "uses a success chip variant `configured` when Voyage credentials " \
     "are present (the default in the test environment via " \
     "`Rails.application.credentials.dig(:voyage, :api_key)`)" do
    # `AppSetting.voyage_configured?` is read directly by the
    # `_voyage_section.html.erb` partial; the `voyage_configured` ivar
    # set above is reserved for legacy call sites and not consulted
    # here. In the test environment `voyage_configured?` returns true
    # (credentials are populated by `bin/rails credentials:edit
    # --environment test`), so Voyage AI renders the `:configured`
    # chip → success variant (per FB-6 two-color rule).
    expect(rendered).to have_css(
      "span.tui-chip.tui-chip--success", text: "configured"
    )
  end

  it "uses the danger chip variant `not configured` when " \
     "`AppSetting.voyage_configured?` flips to false" do
    allow(AppSetting).to receive(:voyage_configured?).and_return(false)
    # Re-render with the stub in place.
    assign(:postgres_status, { connected: true, adapter: "postgresql", database: "pito_test", version: "17" })
    assign(:redis_status, { connected: true, version: "7", used_memory_human: "1MB", db_size: 0, persistence: "rdb" })
    assign(:search_healthy, true)
    assign(:search_per_index_stats, [])
    assign(:postgres_table_breakdown, [])
    assign(:sidekiq_breakdown, [])
    assign(:storage_status, { path: "/tmp", present: true, writable: true, size_bytes: 0, file_count: 0 })
    assign(:notes_volume_status, { present: true, writable: true, size_bytes: 0, file_count: 0 })
    assign(:assets_breakdown, [])
    assign(:notes_breakdown, [])
    assign(:voyage_configured, false)
    render partial: "settings/stack_pane"

    expect(rendered).to have_css(
      "span.tui-chip.tui-chip--danger", text: "not configured"
    )
  end

  it "renders the Postgres model breakdown rows" do
    expect(rendered).to include("channels")
    expect(rendered).to include("videos")
  end

  it "renders the Sidekiq counters block inside the Redis tile" do
    expect(rendered).to include("successful")
    expect(rendered).to include("failed")
    expect(rendered).to include("busy")
  end

  it "renders numeric cells with `.num` (tabular-nums via the global rule)" do
    # The `.num` class carries `font-variant-numeric: tabular-nums` per
    # `app/assets/tailwind/application.css`. Asserting the class on at
    # least the Postgres breakdown rows is enough; the same rule
    # applies to every numeric column in the pane.
    expect(rendered).to have_css("td.num")
  end

  it "renders the reindex link as a bracketed turbo-method POST" do
    # FB-63 — reindex split into per-subsystem actions; each tile
    # owns its own bracketed POST trigger (no JS confirm modal).
    expect(rendered).to include("reindex")
    expect(rendered).to include('href="/settings/stack/meilisearch/reindex"')
  end

  # FB-51/FB-52 V4 — per-tile `border-right` / `border-bottom`
  # assertions are dropped. The new vertical-flex layout uses
  # `.pito-sub-panel` framing instead of inline hairlines between
  # tiles in a grid.
end
