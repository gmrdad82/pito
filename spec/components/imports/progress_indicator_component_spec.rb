require "rails_helper"

# Phase 22 §7.3 — Imports::ProgressIndicatorComponent.
RSpec.describe Imports::ProgressIndicatorComponent, type: :component do
  let(:user)    { build_stubbed(:user) }
  let(:channel) { build_stubbed(:channel) }

  def import_job(**overrides)
    ImportJob.new(channel: channel, enqueued_by: user, status: :queued, **overrides)
  end

  it "renders the `=---` bar empty for a queued job" do
    render_inline(described_class.new(import_job: import_job(status: :queued)))
    expect(page).to have_css("code", text: "----")
    expect(page).to have_text("queued")
  end

  it "renders a half-filled bar for a running job at 50%" do
    job = import_job(status: :running, total_videos: 4, imported_videos: 2)
    render_inline(described_class.new(import_job: job))
    expect(page).to have_css("code", text: "==--")
    expect(page).to have_text("imported 2 of 4")
  end

  it "renders a full bar for a completed job" do
    job = import_job(status: :completed, total_videos: 5, imported_videos: 5)
    render_inline(described_class.new(import_job: job))
    expect(page).to have_css("code", text: "====")
    expect(page).to have_text("completed — 5 new")
  end

  # Regression — the "completed — 0 new" copy was misleading; the user
  # reported the import modal showing the line for channels that
  # genuinely had no upstream uploads. The label now distinguishes
  # three real-world shapes.
  it "renders 'no new uploads' when upstream returned nothing (total==0, imported==0)" do
    job = import_job(status: :completed, total_videos: 0, imported_videos: 0)
    render_inline(described_class.new(import_job: job))
    expect(page).to have_text("no new uploads")
    expect(page).not_to have_text("0 new")
  end

  it "renders the skipped-count variant when total>0 but nothing new (imported==0)" do
    # Every candidate already existed locally (already-imported /
    # previously-rejected) — the importer paged through them all but
    # added 0 rows.
    job = import_job(status: :completed, total_videos: 7, imported_videos: 0)
    render_inline(described_class.new(import_job: job))
    expect(page).to have_text("completed — no new uploads (7 skipped)")
  end

  it "renders an empty bar for a failed job" do
    job = import_job(status: :failed)
    render_inline(described_class.new(import_job: job))
    expect(page).to have_css("code", text: "----")
    expect(page).to have_text("failed")
  end

  it "tags the span with the status class for css targeting" do
    job = import_job(status: :running)
    render_inline(described_class.new(import_job: job))
    expect(page).to have_css("span.imports-progress-running")
  end

  it "exposes the progress fraction as a data attribute" do
    job = import_job(status: :running, total_videos: 10, imported_videos: 3)
    render_inline(described_class.new(import_job: job))
    expect(page).to have_css("span[data-progress-fraction]")
  end

  it "caps a 100% bar at 4 ticks" do
    job = import_job(status: :running, total_videos: 1, imported_videos: 1)
    render_inline(described_class.new(import_job: job))
    expect(page).to have_css("code", text: "====")
  end
end
