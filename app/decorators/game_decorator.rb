# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Decorator for the Rails JSON contract exposed at `GET /games.json`,
# `GET /games/:id.json`, `GET /games/search.json`, and used internally
# by the search jbuilder partial. Boundary booleans serialize as
# `"yes"` / `"no"` strings (CLAUDE.md hard rule) and timestamps as
# ISO-8601.
class GameDecorator < ApplicationDecorator
  def as_summary_json
    {
      id: id,
      slug: igdb_slug,
      title: title,
      release_year: release_year,
      igdb_rating: igdb_rating&.to_f,
      played_at: played_at&.iso8601,
      cover_image_id: cover_image_id,
      resyncing: YesNo.to_yes_no(resyncing?),
      igdb_synced_at: igdb_synced_at&.iso8601,
      created_at: created_at&.iso8601
    }
  end

  def as_detail_json
    as_summary_json.merge(
      igdb_id: igdb_id,
      summary: summary,
      release_date: release_date&.iso8601,
      igdb_rating_count: igdb_rating_count,
      aggregated_rating: aggregated_rating&.to_f,
      total_rating: total_rating&.to_f,
      total_rating_count: total_rating_count,
      ttb_main_seconds: ttb_main_seconds,
      ttb_extras_seconds: ttb_extras_seconds,
      ttb_completionist_seconds: ttb_completionist_seconds,
      external_steam_app_id: external_steam_app_id,
      notes: notes,
      hours_of_footage_manual: hours_of_footage_manual&.to_f,
      hours_of_footage_cached: hours_of_footage_cached&.to_f,
      manual_date_override: YesNo.to_yes_no(manual_date_override),
      last_sync_error: last_sync_error,
      genre: primary_genre&.name,
      updated_at: updated_at&.iso8601
    )
  end
end
