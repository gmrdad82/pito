# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Schedule list response. Page + filter echo lets the CLI / MCP caller
# verify what it asked for; entries[] is the per-row decorator
# summary.
json.page @page
json.total_pages @total_pages
json.total @total
json.per_page Calendar::ScheduleController::PAGE_SIZE
json.selected_kinds(
  case @selected_kinds
  when :empty then []
  when nil    then nil
  else             @selected_kinds
  end
)
json.selected_source @selected_source
json.show_cancelled YesNo.to_yes_no(@show_cancelled)
json.install_tz @install_tz
json.today @today.iso8601

json.entries(@entries) do |entry|
  json.partial! "calendar/entries/entry", entry: entry
end
