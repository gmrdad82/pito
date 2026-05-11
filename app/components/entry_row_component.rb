# Phase 15 §2 — Calendar Views.
#
# Schedule view row. Calendar refactor 2026-05-11: drops the `occurred`
# state column entirely, replaces the legacy glyph prefix with a typed
# `entry_type_label` (`channel(joined)` / `video(published)` / etc.),
# and surfaces all-day entries with a `[ all day ]` badge in the time
# column. Grouping-by-day (suppress repeated date cell) is handled by
# the schedule template — the row carries the date label every time;
# the template overrides it with `show_date: false` for sibling rows.
class EntryRowComponent < ViewComponent::Base
  include CalendarHelper

  def initialize(entry:, indent: false, show_reminder: false, show_date: true)
    @entry = entry
    @indent = indent
    @show_reminder = show_reminder
    @show_date = show_date
  end

  attr_reader :entry, :indent, :show_reminder, :show_date

  def date_label
    entry_date_grouping_label(entry)
  end

  def time_label
    entry_time_label(entry)
  end

  def all_day?
    entry.all_day
  end

  def type_label
    entry_type_label(entry)
  end

  def state_class
    entry_chip_class(entry)
  end

  def title
    entry.title
  end

  # Direct link to the related resource (video / channel / game). Used
  # by the trailing `[open]` action column. Falls back to the entry's
  # own show page for free-form types.
  def open_target_href
    entry_link_target(entry) || Rails.application.routes.url_helpers.calendar_entry_path(entry)
  end

  # URL the modal trigger uses to swap details into the modal's Turbo
  # Frame.
  def details_pane_url
    Rails.application.routes.url_helpers.details_pane_calendar_entry_path(entry)
  end

  # Returns true when this is a future game_release entry whose
  # dispatch-declaration includes pre-release reminders.
  def show_reminder_copy?
    return false unless show_reminder
    return false unless entry.entry_type == "game_release"
    return false if entry.starts_at <= Time.current

    decls = Calendar::NotificationDispatchDeclaration.declarations_for(entry)
    decls.any? { |d| d[:kind] == "game_release_upcoming" }
  end
end
