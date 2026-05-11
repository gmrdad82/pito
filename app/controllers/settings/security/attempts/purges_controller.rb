# Phase 25 — 01f. Bulk-purge the attempt log by filter.
#
# Mirror of `Settings::Security::Blocks::PurgesController` on the
# `login_attempts` table. GET renders the preview + filter summary +
# count; POST consumes `confirm=yes` and calls
# `Auth::AttemptPurger`.
#
# Safety rule (LOCKED): unfiltered calls raise `EmptyFilter`. The
# controller short-circuits with a 422-equivalent redirect so the
# operator can re-enter the filter.
#
# Audit logging: assigned to `Auth::AuditLogger` (01d). A TODO marker
# documents the eventual call site; the visible side effect today is
# the `flash[:notice]` with the deletion count.
class Settings::Security::Attempts::PurgesController < ApplicationController
  def show
    @applied_filter = filter_params
    @no_filter      = filter_blank?

    if @no_filter
      @preview_count = 0
    else
      begin
        scope = build_preview_scope(@applied_filter)
        @preview_count = scope.count
      rescue Auth::AttemptPurger::InvalidFilter => e
        flash.now[:alert] = e.message
        @preview_count = 0
      end
    end
  end

  def create
    if filter_blank?
      redirect_to settings_security_attempts_purge_path,
                  alert: "purge requires at least one filter (safety rule)."
      return
    end

    unless params[:confirm].to_s == "yes"
      redirect_to settings_security_attempts_path,
                  alert: "purge cancelled."
      return
    end

    begin
      result = Auth::AttemptPurger.call(
        filter: filter_params,
        acting_user: Current.user,
        source: :web
      )
    rescue Auth::AttemptPurger::EmptyFilter
      redirect_to settings_security_attempts_purge_path,
                  alert: "purge requires at least one filter (safety rule)."
      return
    rescue Auth::AttemptPurger::InvalidFilter => e
      redirect_to settings_security_attempts_purge_path,
                  alert: e.message
      return
    end

    # TODO(phase-25/01d): wrap with `Auth::AuditLogger.call(
    #   action: :purge, source: :web, acting_user: Current.user,
    #   metadata: { kind: :attempts, filter: result.filter,
    #               deleted_count: result.deleted_count })`.

    redirect_to settings_security_attempts_path,
                notice: "purged #{result.deleted_count} attempt#{'s' if result.deleted_count != 1}."
  end

  private

  def filter_params
    {
      result: params[:result].presence,
      since: params[:since].presence,
      until_ts: params[:until_ts].presence,
      ip: params[:ip].presence,
      fingerprint: params[:fingerprint].presence,
      user_id: params[:user_id].presence
    }
  end

  def filter_blank?
    filter_params.values.all?(&:blank?)
  end

  # Build the same scope the purger does so the preview count matches
  # the eventual deletion count. Kept inline (not a separate service)
  # because it would otherwise become an awkward "ScopeBuilder" mirror
  # of `Auth::AttemptPurger#scoped_relation`; the duplication is
  # narrow and the preview path needs the count, not the rows.
  def build_preview_scope(filter)
    scope = LoginAttempt.all

    if (v = filter[:result].to_s.presence) && LoginAttempt.results.key?(v)
      scope = scope.where(result: LoginAttempt.results[v])
    end

    if (v = filter[:since]).present?
      ts = parse_ts!(v, key: :since)
      scope = scope.where(LoginAttempt.arel_table[:created_at].gteq(ts))
    end

    if (v = filter[:until_ts]).present?
      ts = parse_ts!(v, key: :until_ts)
      scope = scope.where(LoginAttempt.arel_table[:created_at].lteq(ts))
    end

    if (v = filter[:ip].to_s.presence)
      scope = scope.where(ip: v)
    end

    if (v = filter[:fingerprint].to_s.presence)
      scope = scope.where(fingerprint_hash: v)
    end

    if (v = filter[:user_id]).present?
      scope = scope.where(user_id: v.to_i)
    end

    scope
  end

  def parse_ts!(raw, key:)
    Time.iso8601(raw.to_s)
  rescue ArgumentError, TypeError
    raise Auth::AttemptPurger::InvalidFilter, "invalid #{key} timestamp (expected ISO8601)"
  end
end
