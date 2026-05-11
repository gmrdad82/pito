# Phase 25 — 01f. Paginated, filterable lister for the
# `BlockedLocation` table.
#
# Drives:
#
#   - `/settings/security/blocks` (web index)
#   - `blocked_locations_list` MCP tool (read-only)
#   - TUI read-only block list (deferred per 01f acceptance).
#
# Filters (all optional, applied AND-wise):
#
#   - `source_surface` — `"web"` / `"tui"` / `"mcp"` (enum string).
#   - `blocked_by_user_id` — integer FK (matches `BlockedLocation#blocked_by_user_id`).
#   - `since` / `until_ts` — ISO8601 timestamps bracketing `blocked_at`.
#   - `fingerprint` — full SHA256 hex; exact match.
#   - `ip_prefix` — exact match on the CIDR string.
#   - `active` — `"yes"` (only `unblocked_at IS NULL`),
#     `"no"` (only `unblocked_at IS NOT NULL`),
#     anything else / blank → both.
#
# `since` / `until_ts` are validated explicitly because invalid input
# silently widens the result set in `01a`'s precedent and the spec
# (`spec/services/auth/blocked_location_lister_spec.rb`) calls out
# `sad: invalid date → input validation error`.
#
# Output:
#
#   {
#     rows:   ActiveRecord::Relation,
#     total:  Integer,
#     page:   Integer,
#     per_page: Integer,
#     filters: applied filter hash (yes/no Booleans at the boundary)
#   }
#
# The boundary serialization (yes/no for `active`) is the LD-15 rule;
# the caller (controller or MCP tool) is responsible for the final
# render shape, but the lister returns the filter hash with the yes/no
# convention preserved so the round-trip echoes through.
module Auth
  class BlockedLocationLister
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 100

    Result = Struct.new(:rows, :total, :page, :per_page, :filters, keyword_init: true)

    class InvalidFilter < ArgumentError; end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(filters: {}, page: 1, per_page: DEFAULT_PER_PAGE)
      @filters  = (filters || {}).symbolize_keys
      @page     = [ page.to_i, 1 ].max
      @per_page = [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min
    end

    def call
      scope = BlockedLocation.all

      scope = apply_source_surface(scope)
      scope = apply_blocked_by_user(scope)
      scope = apply_since(scope)
      scope = apply_until(scope)
      scope = apply_fingerprint(scope)
      scope = apply_ip_prefix(scope)
      scope = apply_active(scope)

      total = scope.count
      rows  = scope.order(blocked_at: :desc, id: :desc)
                   .offset((@page - 1) * @per_page)
                   .limit(@per_page)

      Result.new(
        rows: rows,
        total: total,
        page: @page,
        per_page: @per_page,
        filters: filters_echo
      )
    end

    private

    def apply_source_surface(scope)
      v = @filters[:source_surface].to_s.presence
      return scope unless v
      return scope unless BlockedLocation.source_surfaces.key?(v)
      scope.where(source_surface: BlockedLocation.source_surfaces[v])
    end

    def apply_blocked_by_user(scope)
      v = @filters[:blocked_by_user_id]
      return scope if v.blank?
      scope.where(blocked_by_user_id: v.to_i)
    end

    def apply_since(scope)
      v = @filters[:since]
      return scope if v.blank?
      ts = parse_ts!(v, key: :since)
      scope.where(BlockedLocation.arel_table[:blocked_at].gteq(ts))
    end

    def apply_until(scope)
      v = @filters[:until_ts] || @filters[:until]
      return scope if v.blank?
      ts = parse_ts!(v, key: :until_ts)
      scope.where(BlockedLocation.arel_table[:blocked_at].lteq(ts))
    end

    def apply_fingerprint(scope)
      v = @filters[:fingerprint].to_s.presence
      return scope unless v
      scope.where(fingerprint_hash: v)
    end

    def apply_ip_prefix(scope)
      v = @filters[:ip_prefix].to_s.presence
      return scope unless v
      scope.where(ip_prefix: v)
    end

    def apply_active(scope)
      v = @filters[:active].to_s.presence
      case v
      when "yes" then scope.where(unblocked_at: nil)
      when "no"  then scope.where.not(unblocked_at: nil)
      else scope
      end
    end

    def parse_ts!(raw, key:)
      Time.iso8601(raw.to_s)
    rescue ArgumentError, TypeError
      raise InvalidFilter, "invalid #{key} timestamp (expected ISO8601)"
    end

    def filters_echo
      {
        source_surface: @filters[:source_surface].presence,
        blocked_by_user_id: @filters[:blocked_by_user_id].presence,
        since: @filters[:since].presence,
        until_ts: (@filters[:until_ts] || @filters[:until]).presence,
        fingerprint: @filters[:fingerprint].presence,
        ip_prefix: @filters[:ip_prefix].presence,
        active: @filters[:active].to_s.presence
      }
    end
  end
end
