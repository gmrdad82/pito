# Phase 15 §2 — Calendar Views.
#
# Schedule view row. Renders date, time, prefix-glyph + title, and
# state. Per Q6 + Q12 + Q13.
class EntryRowComponent < ViewComponent::Base
  include CalendarHelper

  def initialize(entry:, indent: false, show_reminder: false)
    @entry = entry
    @indent = indent
    @show_reminder = show_reminder
  end

  attr_reader :entry, :indent, :show_reminder

  def date_label
    entry_date_label(entry)
  end

  def weekday_label
    install_tz = AppSetting.first&.timezone || "UTC"
    entry.starts_at.in_time_zone(install_tz).strftime("%a").downcase
  end

  def time_label
    label = entry_time_label(entry)
    label.presence || "—"
  end

  def glyph
    entry_chip_glyph(entry)
  end

  def state_class
    entry_chip_class(entry)
  end

  def title
    entry.title
  end

  def state_label
    entry.state
  end

  def link_target
    entry_link_target(entry) || calendar_entry_path(entry)
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

  private

  def calendar_entry_path(e)
    Rails.application.routes.url_helpers.calendar_entry_path(e)
  end
end
