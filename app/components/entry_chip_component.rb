# Phase 15 §2 — Calendar Views.
#
# Compact chip rendered inside month-grid cells. Renders the prefix
# glyph (per Q6), an optional time, and the truncated title. Lowercase
# monospace per `docs/design.md`.
class EntryChipComponent < ViewComponent::Base
  include CalendarHelper

  def initialize(entry:)
    @entry = entry
  end

  attr_reader :entry

  def glyph
    entry_chip_glyph(entry)
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

  def link_target
    entry_link_target(entry) || calendar_entry_path(entry)
  end

  private

  def calendar_entry_path(entry)
    Rails.application.routes.url_helpers.calendar_entry_path(entry)
  end
end
