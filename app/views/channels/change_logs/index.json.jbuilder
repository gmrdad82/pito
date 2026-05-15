# Phase 7.5 §11g — Channel Change History JSON envelope.
#
# Matches the Phase 21 list-endpoint contract: a plural-noun array
# (`changes`) + a `pagination` object. Per the locked decisions on
# the 10 open questions:
#   - envelope key is `changes` (not `change_logs` — implementation
#     detail of the model name).
#   - `created_at` is NOT exposed (identical to `changed_at` for
#     append-only rows).
#   - `changed_by` is `{ id, username }` when the FK resolves, or
#     `null` when the FK is nil (system-generated rows).
#   - `changed_at` is ISO-8601 UTC.
json.changes(@logs) do |log|
  json.id log.id
  json.field log.field
  json.old_value log.old_value
  json.new_value log.new_value
  json.changed_at log.changed_at.utc.iso8601
  if log.changed_by_user
    json.changed_by do
      json.id log.changed_by_user.id
      json.username log.changed_by_user.username
    end
  else
    json.changed_by nil
  end
end

json.pagination do
  json.page @page
  json.per_page @per_page
  json.total @total
  json.total_pages @total_pages
end
