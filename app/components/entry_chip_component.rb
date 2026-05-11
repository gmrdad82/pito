# Phase 15 §2 — Calendar Views.
#
# Compact chip rendered inside month-grid cells. Calendar refactor
# 2026-05-11: the chip now renders a typed token label
# (`channel(joined)`, `game(released)`, `milestone`, etc.) instead of
# the legacy single-letter glyph prefix. Clicking the chip opens the
# entry's details modal (the `[ open <target> ]` link inside the modal
# is the actual cross-link to the related resource).
class EntryChipComponent < ViewComponent::Base
  include CalendarHelper

  def initialize(entry:)
    @entry = entry
  end

  attr_reader :entry

  def type_label
    entry_type_label(entry)
  end

  def time_label
    entry_time_label(entry)
  end

  def title
    entry_chip_title(entry)
  end

  def state_class
    entry_chip_class(entry)
  end

  # Fallback `href` for JS-off / direct-link visitors. The Stimulus
  # `calendar-entry-modal#open` action intercepts the click and opens
  # the modal instead, but the underlying link still points at the
  # canonical entry show page so the chip remains a working link
  # without JS.
  def fallback_href
    Rails.application.routes.url_helpers.calendar_entry_path(entry)
  end

  # URL the Stimulus controller fetches into the modal's Turbo Frame.
  def details_pane_url
    Rails.application.routes.url_helpers.details_pane_calendar_entry_path(entry)
  end
end
