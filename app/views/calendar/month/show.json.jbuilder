# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Month grid response. Buckets is a date-keyed hash of entries arrays;
# empty days are omitted (callers fill them with empty arrays locally).
json.year @year
json.month @month
json.install_tz @install_tz
json.first_day @first_day.iso8601
json.last_day @last_day.iso8601
json.today @today.iso8601
json.on_current_month YesNo.to_yes_no(@on_current_month)
json.selected_kinds(
  case @selected_kinds
  when :empty then []
  when nil    then nil
  else             @selected_kinds
  end
)
json.show_cancelled YesNo.to_yes_no(params[:state] == "all")

json.buckets do
  # jbuilder emits `null` when the block yields no calls. Guard the
  # empty-bucket case so the wire shape stays `"buckets": {}`.
  if @buckets.empty?
    json.merge!({})
  else
    @buckets.each do |date, entries|
      json.set!(date.iso8601) do
        json.array!(entries) do |entry|
          json.partial! "calendar/entries/entry", entry: entry
        end
      end
    end
  end
end

json.nav do
  json.prev { json.year @prev_year; json.month @prev_month }
  json.next { json.year @next_year; json.month @next_month }
end
