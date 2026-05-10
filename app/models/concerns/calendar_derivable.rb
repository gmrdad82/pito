# Phase 15 §1 — Calendar Data Model.
#
# Mixin for host models (Channel, Video, Game) that derive a
# `CalendarEntry` row. Each host implements three methods:
#   - `calendar_entry_type` — returns the symbol for the entry_type the
#     host should derive RIGHT NOW (or nil to revoke).
#   - `calendar_entry_attributes` — the attribute hash the upsert
#     applies. Returns nil to signal "no derived entry for this host
#     state right now" (the upsert flips any prior derived entry to
#     `:superseded`).
#   - `calendar_entry_source_ref` — the jsonb pointer to use for the
#     `(entry_type, source_ref)` upsert lookup.
#
# The host wires the mixin's `sync_calendar_entry` call into its own
# `after_save` chain, gated on the relevant attribute changes.
module CalendarDerivable
  extend ActiveSupport::Concern

  def derive_calendar_entry!
    Calendar::Derivation.sync!(self)
  end

  def revoke_calendar_entry!
    Calendar::Derivation.revoke!(self)
  end

  # Convenience: the host's after_save hook calls this; service decides
  # between sync (attrs present) and revoke (attrs nil).
  #
  # When the host's current state has no derivation (`attrs == nil`),
  # we need to supersede ALL prior derived entries tied to this host,
  # not just one keyed on the current source_ref. Because Video can
  # flip between `video_published` and `video_scheduled` shapes (and
  # between either and "no derivation"), the prior entry's source_ref
  # may not match the current `calendar_entry_source_ref`. The
  # service handles this via `revoke_all_for_host!`.
  def sync_calendar_entry
    if calendar_entry_attributes.nil?
      Calendar::Derivation.revoke_all_for_host!(self)
    else
      Calendar::Derivation.sync!(self)
    end
  end
end
