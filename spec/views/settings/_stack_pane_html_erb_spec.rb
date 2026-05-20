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
    expect(rendered).to include("<h2>stack</h2>")
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

  it "lays out the inner pane as a 2-column tile grid via `.stack-pane-grid` " \
     "with `grid-template-columns: 1fr 1fr` inline override" do
    # Beta 4 F3-D — the existing `.stack-pane-grid` class is reused
    # but its 3-col `1fr 1px 1fr` rule is overridden inline to a flat
    # 2-col tile grid. No `.stack-pane-divider` element — the vertical
    # hairline moves into per-tile `border-right`.
    expect(rendered).to include('class="stack-pane-grid"')
    expect(rendered).to include("grid-template-columns: 1fr 1fr")
    expect(rendered).not_to include('class="stack-pane-divider"')
  end

  it "renders a Tui::ChipComponent status chip for each of the six subsystems" do
    # `Settings::Stack::HealthLineComponent` delegates to
    # `Tui::ChipComponent`, which renders a `span.tui-chip` with one
    # variant modifier per subsystem. Six chips total (one per tile):
    # PostgreSQL, Meilisearch, Redis, Voyage AI, assets, notes.
    expect(rendered).to have_css("span.tui-chip", count: 6)
  end

  it "uses the success chip variant for the connected Postgres status" do
    expect(rendered).to have_css(
      "span.tui-chip.tui-chip--success", text: "[connected]"
    )
  end

  it "uses the info chip variant for the writable assets status" do
    expect(rendered).to have_css(
      "span.tui-chip.tui-chip--info", text: "[writable]"
    )
  end

  it "uses an info chip variant `[configured]` when Voyage credentials " \
     "are present (the default in the test environment via " \
     "`Rails.application.credentials.dig(:voyage, :api_key)`)" do
    # `AppSetting.voyage_configured?` is read directly by the
    # `_voyage_section.html.erb` partial; the `voyage_configured` ivar
    # set above is reserved for legacy call sites and not consulted
    # here. In the test environment `voyage_configured?` returns true
    # (credentials are populated by `bin/rails credentials:edit
    # --environment test`), so Voyage AI renders the `:configured`
    # chip → info variant.
    expect(rendered).to have_css(
      "span.tui-chip.tui-chip--info", text: "[configured]"
    )
  end

  it "uses the danger chip variant `[not configured]` when " \
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
      "span.tui-chip.tui-chip--danger", text: "[not configured]"
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

  it "renders the reindex link wired to the confirm modal" do
    expect(rendered).to include("reindex")
    expect(rendered).to include("reindex_meilisearch_modal")
  end

  it "renders hairline borders between tiles via inline `border-right` " \
     "(odd columns) and `border-bottom` (top two rows)" do
    # Four tiles carry `border-right` (rows 1-3 × col 1 = 3 tiles, but
    # only the left tiles need a right border = 3 tiles). The bottom
    # two rows-of-tiles carry `border-bottom` (rows 1 + 2 = 4 tiles).
    # Asserting the presence of both border declarations is enough —
    # the per-tile count varies as the layout evolves.
    expect(rendered).to include("border-right: 1px solid var(--color-border)")
    expect(rendered).to include("border-bottom: 1px solid var(--color-border)")
  end
end
