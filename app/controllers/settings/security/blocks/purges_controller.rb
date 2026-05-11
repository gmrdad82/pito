# Phase 25 — 01f. Bulk-purge the auto-block list by filter.
#
# Action-screen pattern (mirrors `DeletionsController` /
# `SyncsController`): GET renders the preview + filter summary + count
# of rows that will be hard-deleted; POST consumes the `confirm=yes`
# form and calls `Auth::BlockedLocationPurger`.
#
# Safety rule (LOCKED): the purger raises `EmptyFilter` if no filter
# field is supplied; we catch that early and surface a 422 with a
# notice so the operator can re-enter the filter.
#
# Yes/no boundary (LD-15): the `confirm` form param is `"yes"` /
# anything else. Anything else is treated as cancel.
#
# Audit logging: the spec assigns audit-log writes to
# `Auth::AuditLogger`, introduced in 01d. Until that service lands the
# purge action records the count + filter in `flash[:notice]` only;
# the structured audit row is appended once 01d ships and adds the
# call site here (a TODO marker, not a silent gap).
class Settings::Security::Blocks::PurgesController < ApplicationController
  def show
    @applied_filter = filter_params
    @no_filter      = filter_blank?

    # Preview count uses the lister with the same filter (lister and
    # purger share the filter shape so the preview matches the
    # destructive call). Bail out cleanly on invalid timestamps.
    if @no_filter
      @preview_count = 0
    else
      begin
        result = Auth::BlockedLocationLister.call(
          filters: @applied_filter,
          page: 1,
          per_page: 1
        )
        @preview_count = result.total
      rescue Auth::BlockedLocationLister::InvalidFilter => e
        flash.now[:alert] = e.message
        @preview_count = 0
      end
    end
  end

  def create
    if filter_blank?
      redirect_to settings_security_blocks_purge_path,
                  alert: "purge requires at least one filter (safety rule)."
      return
    end

    unless params[:confirm].to_s == "yes"
      redirect_to settings_security_blocks_path,
                  alert: "purge cancelled."
      return
    end

    begin
      result = Auth::BlockedLocationPurger.call(
        filter: filter_params,
        acting_user: Current.user,
        source: :web
      )
    rescue Auth::BlockedLocationPurger::EmptyFilter
      redirect_to settings_security_blocks_purge_path,
                  alert: "purge requires at least one filter (safety rule)."
      return
    rescue Auth::BlockedLocationPurger::InvalidFilter => e
      redirect_to settings_security_blocks_purge_path,
                  alert: e.message
      return
    end

    # TODO(phase-25/01d): wrap with `Auth::AuditLogger.call(
    #   action: :purge, source: :web, acting_user: Current.user,
    #   metadata: { kind: :blocks, filter: result.filter,
    #               deleted_count: result.deleted_count })` once the
    # audit logger ships.

    redirect_to settings_security_blocks_path,
                notice: "purged #{result.deleted_count} block#{'s' if result.deleted_count != 1}."
  end

  private

  def filter_params
    {
      source_surface: params[:source_surface].presence,
      blocked_by_user_id: params[:blocked_by_user_id].presence,
      since: params[:since].presence,
      until_ts: params[:until_ts].presence,
      fingerprint: params[:fingerprint].presence,
      ip_prefix: params[:ip_prefix].presence,
      active: params[:active].presence
    }
  end

  def filter_blank?
    filter_params.values.all?(&:blank?)
  end
end
