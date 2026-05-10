# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# IGDB type-ahead. Locked decision #8: upstream errors render HTTP 200
# with `results: []` and a populated `search_error: { kind, message }`.
# The caller distinguishes via the `search_error` field.
json.query @query

json.results(@results) do |result|
  json.igdb_id      result["id"]
  json.title        result["name"]
  json.release_year(
    if result["first_release_date"].present?
      Time.at(result["first_release_date"].to_i).utc.year
    end
  )
  json.cover_image_id(result.dig("cover", "image_id"))
  json.summary      result["summary"]
end

json.took_ms @took_ms

if @search_error.is_a?(Hash)
  json.search_error do
    json.kind    @search_error[:kind]
    json.message @search_error[:message]
  end
else
  json.search_error nil
end
