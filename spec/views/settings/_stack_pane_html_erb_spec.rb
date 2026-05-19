require "rails_helper"

# Phase 29 (settings refactor) — stack pane partial (row 3, wide).
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
    # 2026-05-19 — Voyage's section heading is sourced from
    # `settings.voyage.heading` ("Voyage AI"), not the older
    # "Voyage embeddings" copy. All six stack surfaces still render:
    # Postgres + Redis (db column), Meilisearch + Voyage AI + assets +
    # notes (search/storage column).
    expect(rendered).to include("Postgres")
    expect(rendered).to include("Redis")
    expect(rendered).to include("Meilisearch")
    expect(rendered).to include("Voyage AI")
    expect(rendered).to include("assets")
    expect(rendered).to include("notes")
  end

  it "renders the Postgres model breakdown rows" do
    expect(rendered).to include("channels")
    expect(rendered).to include("videos")
  end

  it "renders the Sidekiq stats grouped table" do
    expect(rendered).to include("successful")
    expect(rendered).to include("failed")
    expect(rendered).to include("busy")
  end

  it "renders the reindex link wired to the confirm modal" do
    expect(rendered).to include("reindex")
    expect(rendered).to include("reindex_meilisearch_modal")
  end
end
