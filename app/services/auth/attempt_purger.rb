# Phase 25 — 01f. Bulk-delete `login_attempts` rows by filter. Hard
# delete; attempts are durable by default (no auto-purge) and only
# disappear when an operator runs this purger from the web purge UI,
# the MCP `login_attempt_purge` tool (introduced in 01d, reuses this
# service), or a future TUI surface.
#
# Safety rule (LOCKED in this sub-spec): every call must include at
# least one filter. An unfiltered call raises `EmptyFilter` so an
# operator cannot accidentally wipe the entire attempt log.
#
# Filter set mirrors the read paths (`LoginAttempt` scopes +
# `LoginAttemptsList` MCP tool):
#
#   - `result`       — enum string (success / failed / pending_approval / blocked / rate_limited).
#   - `since`        — ISO8601 ts; rows with `created_at >= since`.
#   - `until_ts`     — ISO8601 ts; rows with `created_at <= until_ts`.
#   - `ip`           — exact match on `LoginAttempt#ip` (inet equality).
#   - `fingerprint`  — exact match on `fingerprint_hash`.
#   - `user_id`      — integer FK on `LoginAttempt#user_id`.
#
# Audit-logging is the caller's responsibility — the controller / MCP
# tool wraps this call with the `Auth::AuditLogger` write once that
# ships in 01d.
module Auth
  class AttemptPurger
    BATCH_SIZE = 1_000

    Result = Struct.new(:deleted_count, :filter, keyword_init: true)

    class EmptyFilter < ArgumentError; end
    class InvalidFilter < ArgumentError; end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(filter: {}, acting_user: nil, source: :web)
      @filter      = (filter || {}).symbolize_keys
      @acting_user = acting_user
      @source      = source
    end

    def call
      raise EmptyFilter, "purge requires at least one filter" if no_filter_supplied?

      scope, applied_any = scoped_relation
      raise EmptyFilter, "purge requires at least one filter" unless applied_any

      deleted = delete_in_batches(scope)
      Result.new(deleted_count: deleted, filter: echoed_filter)
    end

    private

    def no_filter_supplied?
      keys = %i[result since until_ts until ip fingerprint user_id]
      keys.none? { |k| @filter[k].to_s.strip.presence }
    end

    # Returns [scope, applied_any]. `applied_any` flips true whenever a
    # filter actually narrowed the scope. Filters supplied but ignored
    # (e.g. `result: "bogus"`) leave `applied_any` false so the caller
    # rejects rather than wiping the whole table.
    def scoped_relation
      scope = LoginAttempt.all
      applied = false

      if (v = @filter[:result].to_s.presence) && LoginAttempt.results.key?(v)
        scope = scope.where(result: LoginAttempt.results[v])
        applied = true
      end

      if (v = @filter[:since]).present?
        ts = parse_ts!(v, key: :since)
        scope = scope.where(LoginAttempt.arel_table[:created_at].gteq(ts))
        applied = true
      end

      if (v = (@filter[:until_ts] || @filter[:until])).present?
        ts = parse_ts!(v, key: :until_ts)
        scope = scope.where(LoginAttempt.arel_table[:created_at].lteq(ts))
        applied = true
      end

      if (v = @filter[:ip].to_s.presence)
        scope = scope.where(ip: v)
        applied = true
      end

      if (v = @filter[:fingerprint].to_s.presence)
        scope = scope.where(fingerprint_hash: v)
        applied = true
      end

      if (v = @filter[:user_id]).present?
        scope = scope.where(user_id: v.to_i)
        applied = true
      end

      [ scope, applied ]
    end

    # Delete in batches of `BATCH_SIZE` to keep transactions small.
    # `delete_all` skips callbacks — that is intentional; LoginAttempt
    # has none beyond `before_update :stamp_resolved_at_on_resolution`
    # which is irrelevant on delete.
    def delete_in_batches(scope)
      total = 0
      loop do
        ids = scope.limit(BATCH_SIZE).pluck(:id)
        break if ids.empty?
        total += LoginAttempt.where(id: ids).delete_all
        break if ids.size < BATCH_SIZE
      end
      total
    end

    def parse_ts!(raw, key:)
      Time.iso8601(raw.to_s)
    rescue ArgumentError, TypeError
      raise InvalidFilter, "invalid #{key} timestamp (expected ISO8601)"
    end

    def echoed_filter
      {
        result: @filter[:result].presence,
        since: @filter[:since].presence,
        until_ts: (@filter[:until_ts] || @filter[:until]).presence,
        ip: @filter[:ip].presence,
        fingerprint: @filter[:fingerprint].presence,
        user_id: @filter[:user_id].presence
      }
    end
  end
end
