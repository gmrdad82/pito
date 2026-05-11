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
    when "completed" then "completed — #{@import_job.imported_videos} new"
    when "failed"    then "failed"
    end
  end

  def status_class
    "imports-progress-#{@import_job.status}"
  end
end
