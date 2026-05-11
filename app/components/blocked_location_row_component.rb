# Phase 25 — 01f. One row in the auto-block list table. Reused by:
#
#   - `/settings/security/blocks` index table
#   - `/settings/security/blocks/:id` detail page (kept inline today;
#     the component is ready to slot in when the show page picks up
#     the table layout).
#
# Single-purpose presenter: takes one `BlockedLocation`, renders the
# columns the table needs. Display logic delegates to
# `BlockedLocationsHelper` so the index table + the detail page +
# any future surface share the same vocabulary.
#
# The `[unblock]` bracketed-link is rendered for active rows only.
# Soft-unblocked rows show a muted "unblocked" note in its place so
# the audit history stays visible without offering an idempotent
# re-unblock action.
class BlockedLocationRowComponent < ViewComponent::Base
  include BlockedLocationsHelper

  def initialize(row:, show_view_link: true, show_unblock_link: true)
    @row = row
    @show_view_link = show_view_link
    @show_unblock_link = show_unblock_link
  end

  attr_reader :row

  def show_view_link?
    @show_view_link
  end

  def show_unblock_link?
    @show_unblock_link && row.active?
  end

  def soft_unblocked?
    !row.active?
  end

  def source_badge
    blocked_location_source_badge(row)
  end

  def state_label
    blocked_location_state_label(row)
  end

  def state_css
    blocked_location_state_css(row)
  end

  def fingerprint_short
    row.fingerprint_hash.to_s[0, 12]
  end

  def blocked_at_label
    row.blocked_at.utc.strftime("%Y-%m-%d %H:%M")
  end

  def last_attempt_label
    return "—" unless row.last_attempt_at
    row.last_attempt_at.utc.strftime("%Y-%m-%d %H:%M")
  end
end
