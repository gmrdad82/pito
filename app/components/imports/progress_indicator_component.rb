# Phase 22 §7.3 — per-channel import progress indicator.
#
# Renders the textual `=---` indicator alongside the counter label
# ("imported N of M" / "queued" / "completed" / "failed"). The
# rendering is deliberately monospaced + plain-text so the same fragment
# works inside the modal AND the channel-show in-flight badge.
class Imports::ProgressIndicatorComponent < ViewComponent::Base
  TOTAL_TICKS = 4

  def initialize(import_job:)
    @import_job = import_job
  end

  # Returns a 4-char ASCII progress bar (`=---`, `==--`, `====`, ...).
  def bar
    filled = (TOTAL_TICKS * @import_job.progress_fraction).round
    filled = [ [ filled, 0 ].max, TOTAL_TICKS ].min
    ("=" * filled) + ("-" * (TOTAL_TICKS - filled))
  end

  def label
    case @import_job.status
    when "queued"    then "queued"
    when "running"   then "imported #{@import_job.imported_videos} of #{@import_job.total_videos}"
    when "completed" then completed_label
    when "failed"    then "failed"
    end
  end

  def status_class
    "imports-progress-#{@import_job.status}"
  end

  private

  # `completed` covers three real-world shapes:
  #
  #   - imported > 0           — "completed — N new"
  #   - imported == 0, total > 0  — every candidate was already
  #     imported or previously rejected; not a no-op, but no new
  #     rows landed: "completed — no new uploads (M skipped)".
  #   - imported == 0, total == 0 — upstream returned nothing (no
  #     uploads on the channel, or the connection has not yet wired
  #     in a real playlist client): "no new uploads".
  #
  # The third branch removes the misleading "completed — 0 new" copy
  # the user reported on the import modal.
  def completed_label
    imported = @import_job.imported_videos.to_i
    total    = @import_job.total_videos.to_i

    return "completed — #{imported} new" if imported.positive?
    return "no new uploads" if total.zero?

    "completed — no new uploads (#{total} skipped)"
  end
end
