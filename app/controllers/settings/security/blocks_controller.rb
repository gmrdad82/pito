# Phase 25 — 01f. Paginated, filterable read-only listing of
# `BlockedLocation` rows plus a detail page.
#
# Filters (all optional, AND-applied) — wired through to
# `Auth::BlockedLocationLister`:
#
#   - `source_surface` — `"web"` / `"tui"` / `"mcp"`.
#   - `blocked_by_user_id` — integer.
#   - `since` / `until_ts` — ISO8601 bracketing `blocked_at`.
#   - `fingerprint` — full SHA256 hex.
#   - `ip_prefix` — exact CIDR.
#   - `active` — yes / no boundary (LD-15). Anything else / blank
#     returns both active and soft-unblocked rows.
#
# Invalid timestamp filters bubble back as a flash notice so the
# operator can correct the query; the page still renders the full
# (unfiltered-by-time) set so the surface degrades rather than 500ing.
#
# Auth: cookie-session gate (inherits `Sessions::AuthConcern` from
# `ApplicationController`). Single-install / multi-user (ADR 0003) —
# any authenticated user sees the full install-wide block list.
class Settings::Security::BlocksController < ApplicationController
  PER_PAGE = 50

  def index
    page     = [ params[:page].to_i, 1 ].max
    per_page = PER_PAGE

    begin
      result = Auth::BlockedLocationLister.call(
        filters: filter_params,
        page: page,
        per_page: per_page
      )
    rescue Auth::BlockedLocationLister::InvalidFilter => e
      flash.now[:alert] = e.message
      result = Auth::BlockedLocationLister.call(
        filters: filter_params.except(:since, :until_ts, :until),
        page: page,
        per_page: per_page
      )
    end

    @rows             = result.rows
    @total            = result.total
    @page             = result.page
    @per_page         = result.per_page
    @applied_filters  = result.filters
  end

  def show
    @row = BlockedLocation.find(params[:id])
  end

  private

  def filter_params
    {
      source_surface: params[:source_surface],
      blocked_by_user_id: params[:blocked_by_user_id],
      since: params[:since],
      until_ts: params[:until_ts],
      fingerprint: params[:fingerprint],
      ip_prefix: params[:ip_prefix],
      active: params[:active]
    }
  end
end
