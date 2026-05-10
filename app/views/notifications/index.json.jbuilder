# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Notification index response. Echoes the filter / kind / severity the
# caller asked for so the CLI / MCP caller can verify what it asked for.
json.page @page
json.total_pages @total_pages
json.total @total
json.per_page NotificationsController::PER_PAGE
json.filter @filter
json.kind @kind
json.severity @severity
json.unread_count @unread_count
json.has_failures YesNo.to_yes_no(@has_failures)

json.notifications(@notifications) do |notification|
  json.partial! "notifications/notification", notification: notification
end
