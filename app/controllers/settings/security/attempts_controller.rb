# Phase 25 — 01a. Paginated, filterable read-only attempt log.
#
# Filters (all optional, applied as AND):
#
#   - `result=success|failed|pending_approval|blocked|rate_limited`
#   - `since=<iso8601>` — show rows created at-or-after this timestamp.
#   - `ip=<exact>`        — exact match (PostgreSQL inet equality).
#   - `fingerprint=<hash>` — exact match on the full SHA256 hex.
#
# Unknown / invalid values are silently ignored — the filter narrows
# the result set rather than erroring out, matching the convention on
# notifications + channels index pages.
#
# JSON branch (Phase 21-style parity with CLI / MCP) returns the same
# rows shaped per `LoginAttemptsJsonPresenter`. External booleans go
# through the yes/no boundary per LD-15.
class Settings::Security::AttemptsController < ApplicationController
  PER_PAGE = 50

  def index
    scope = filtered_scope.recent
    page = [ params[:page].to_i, 1 ].max
    @page = page
    @per_page = PER_PAGE
    @total = scope.count
    @attempts = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    @applied_filters = {
      result: params[:result].presence,
      since:  params[:since].presence,
      ip:     params[:ip].presence,
      fingerprint: params[:fingerprint].presence
    }

    respond_to do |format|
      format.html
      format.json { render json: json_payload }
    end
  end

  def show
    @attempt = LoginAttempt.find(params[:id])

    respond_to do |format|
      format.html
      format.json { render json: row_json(@attempt) }
    end
  end

  private

  def filtered_scope
    scope = LoginAttempt.all

    if (result = params[:result].presence) && LoginAttempt.results.key?(result.to_s)
      scope = scope.where(result: LoginAttempt.results[result.to_s])
    end

    if (since_param = params[:since].presence)
      begin
        ts = Time.iso8601(since_param.to_s)
        scope = scope.since(ts)
      rescue ArgumentError
        # ignore malformed timestamps; user sees full result set.
      end
    end

    if (ip = params[:ip].presence)
      scope = scope.for_ip(ip)
    end

    if (fp = params[:fingerprint].presence)
      scope = scope.for_fingerprint(fp)
    end

    scope
  end

  def json_payload
    {
      attempts: @attempts.map { |row| row_json(row) },
      pagination: {
        page: @page,
        per_page: @per_page,
        total: @total
      }
    }
  end

  # Boundary serialization: every Boolean is `"yes"` / `"no"` per
  # LD-15. The `is_success` / `is_failed` / `is_blocked` keys are
  # derived (the model's `result` is the canonical enum); we surface
  # the booleans for callers that want a simple yes/no truth check
  # without parsing the enum string.
  def row_json(attempt)
    {
      id: attempt.id,
      created_at: attempt.created_at.utc.iso8601,
      result: attempt.result,
      reason: attempt.reason,
      is_success: attempt.result_success? ? "yes" : "no",
      is_failed:  attempt.result_failed?  ? "yes" : "no",
      is_blocked: attempt.result_blocked? ? "yes" : "no",
      ip: attempt.ip.to_s,
      ip_prefix: attempt.ip_prefix,
      geo: {
        city:    attempt.geo_city,
        region:  attempt.geo_region,
        country: attempt.geo_country
      },
      user_agent: attempt.user_agent,
      browser: attempt.browser,
      os: attempt.os,
      fingerprint_hash: attempt.fingerprint_hash,
      fingerprint_short: attempt.fingerprint_short,
      user_id: attempt.user_id,
      email_attempted: attempt.email_attempted
    }
  end
end
