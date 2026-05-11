require "rails_helper"

# Phase 22 §7.3 — Imports::ProgressIndicatorComponent.
RSpec.describe Imports::ProgressIndicatorComponent, type: :component do
  let(:user)    { create(:user) }
  let(:channel) { create(:channel) }

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
