# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Entry detail response. `entry` carries the summary + the detail
# extension (parent / child id mirror, etc.) per
# `CalendarEntryDecorator#as_detail_json`. `dispatch_declarations` is a
# top-level sibling array that maps from
# `Calendar::NotificationDispatchDeclaration.declarations_for(@entry)`.
decorator = CalendarEntryDecorator.new(@entry)
json.entry decorator.as_detail_json
json.dispatch_declarations decorator.dispatch_declarations_json
# Phase 7.5 §11h — idempotency marker for the channel-rename-unlock
# reminder. The controller sets `@duplicate = true` on a 200 idempotent
# hit (existing entry returned) so the Stimulus controller renders the
# "already exists" toast instead of "created".
json.duplicate "yes" if @duplicate
