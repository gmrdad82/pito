# Phase 25 — 01f. Bulk-delete blocked_locations rows by filter. Hard
# delete (not soft-unblock) — unlike `BlockedLocationUnblocker`
# (introduced in 01d) which flips `unblocked_at` to preserve the audit
# row, this purger removes rows from the table entirely.
#
# Safety rule (mirrors `Auth::AttemptPurger` and the locked decision in
# this sub-spec): every call must include at least one filter. An
# unfiltered call raises so the operator cannot accidentally wipe the
# entire block list.
#
# Filter set matches `Auth::BlockedLocationLister`:
#
#   - `source_surface`, `blocked_by_user_id`, `since`, `until_ts`,
#     `fingerprint`, `ip_prefix`, `active`
#
# `since` / `until_ts` bracket `blocked_at` for symmetry with the
# lister. `active: "yes"` purges only currently-active rows;
# `active: "no"` purges only the already-soft-unblocked audit rows
# (operator decides which path to take). Defaults to both.
#
# Batched delete: chunks of `BATCH_SIZE` keep transactions small for
# very-large block-lists (10k+). The total deleted count is summed
# across batches and returned. Audit-logging is the caller's
# responsibility — the controller / MCP tool wraps this call with the
# `Auth::AuditLogger` write once that ships in 01d.
module Auth
  class BlockedLocationPurger
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
      keys = %i[source_surface blocked_by_user_id since until_ts until fingerprint ip_prefix active]
      keys.none? { |k| @filter[k].to_s.strip.presence }
    end

    # Returns [scope, applied_any]. `applied_any` flips true whenever a
    # filter actually narrowed the scope. Filters supplied-but-ignored
    # (e.g. `source_surface: "bogus"`) leave it false so the caller
    # rejects rather than wiping the whole table.
    def scoped_relation
      scope = BlockedLocation.all
      applied = false

      if (v = @filter[:source_surface].to_s.presence) && BlockedLocation.source_surfaces.key?(v)
        scope = scope.where(source_surface: BlockedLocation.source_surfaces[v])
        applied = true
      end

      if (v = @filter[:blocked_by_user_id]).present?
        scope = scope.where(blocked_by_user_id: v.to_i)
        applied = true
      end

      if (v = @filter[:since]).present?
        ts = parse_ts!(v, key: :since)
        scope = scope.where(BlockedLocation.arel_table[:blocked_at].gteq(ts))
        applied = true
      end

      if (v = (@filter[:until_ts] || @filter[:until])).present?
        ts = parse_ts!(v, key: :until_ts)
        scope = scope.where(BlockedLocation.arel_table[:blocked_at].lteq(ts))
        applied = true
      end

      if (v = @filter[:fingerprint].to_s.presence)
        scope = scope.where(fingerprint_hash: v)
        applied = true
      end

      if (v = @filter[:ip_prefix].to_s.presence)
        scope = scope.where(ip_prefix: v)
        applied = true
      end

      case @filter[:active].to_s.presence
      when "yes"
        scope = scope.where(unblocked_at: nil)
        applied = true
      when "no"
        scope = scope.where.not(unblocked_at: nil)
        applied = true
      end

      [ scope, applied ]
    end

    # Delete in batches of `BATCH_SIZE` to keep transactions small.
    # Returns total rows deleted.
    def delete_in_batches(scope)
      total = 0
      loop do
        ids = scope.limit(BATCH_SIZE).pluck(:id)
        break if ids.empty?
        total += BlockedLocation.where(id: ids).delete_all
        # Stop if we deleted fewer than BATCH_SIZE — no more work.
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
        source_surface: @filter[:source_surface].presence,
        blocked_by_user_id: @filter[:blocked_by_user_id].presence,
        since: @filter[:since].presence,
        until_ts: (@filter[:until_ts] || @filter[:until]).presence,
        fingerprint: @filter[:fingerprint].presence,
        ip_prefix: @filter[:ip_prefix].presence,
        active: @filter[:active].to_s.presence
      }
    end
  end
end
