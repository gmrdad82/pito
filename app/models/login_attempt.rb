# Phase 25 — 01a. Persistent record of every login attempt.
#
# Each row is durable — there is no auto-purge. Manual purge surfaces
# ship in 01d (MCP `login_attempt_purge`) and 01f (web bulk purge).
#
# `result` and `reason` are integer-backed enums; the public symbol
# set is the locked LD-1 vocabulary. 01a only writes a subset
# (`success`, `failed`, `blocked` results; `wrong_password`,
# `unknown_account`, `blocked_pair`, and `rate_limited` reasons). The
# other enum values are pre-declared so the schema is forward-
# compatible with 01b–01g without another migration.
class LoginAttempt < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :notification, optional: true
  belongs_to :approved_by_user,
             class_name: "User",
             foreign_key: :approved_by_user_id,
             optional: true
  # Phase 25 — 01b. Optional FK to the Session row this attempt spawned.
  # Set on the trusted-location success path, the new-location pending
  # path, the approve/2FA-success transitions, and the pending-expired
  # sweep. `optional: true` because 01a's failed / blocked / unknown-email
  # paths never mint a session.
  belongs_to :session, optional: true

  enum :result, {
    success: 0,
    failed: 1,
    pending_approval: 2,
    blocked: 3,
    rate_limited: 4
  }, prefix: :result

  enum :reason, {
    wrong_password: 0,
    unknown_account: 1,
    new_location_pending: 2,
    new_location_2fa_passed: 3,
    trusted_location_success: 4,
    blocked_pair: 5,
    rate_limited: 6,
    twofa_failed: 7,
    approved_from_web: 8,
    approved_from_tui: 9,
    approved_from_mcp: 10,
    blocked_from_web: 11,
    blocked_from_tui: 12,
    blocked_from_mcp: 13,
    pending_expired: 14
  }, prefix: :reason

  validates :result, presence: true
  validates :reason, presence: true
  validates :ip, presence: true
  validates :ip_prefix, presence: true
  validates :user_agent, presence: true, allow_blank: true
  validates :fingerprint_hash, presence: true, length: { is: 64 }
  validate :ip_prefix_family_matches_ip

  scope :recent,           -> { order(created_at: :desc) }
  scope :failed,           -> { where(result: results[:failed]) }
  scope :succeeded,        -> { where(result: results[:success]) }
  scope :blocked_results,  -> { where(result: results[:blocked]) }
  scope :pending,          -> { where(result: results[:pending_approval]) }
  scope :for_user,         ->(user) { where(user_id: user&.id) }
  scope :for_fingerprint,  ->(fp) { where(fingerprint_hash: fp) }
  scope :for_ip,           ->(ip) { where(ip: ip) }
  scope :since,            ->(ts) { where(arel_table[:created_at].gteq(ts)) }

  # When the row transitions OUT of `pending_approval` (approve / block
  # / expire), stamp `resolved_at`. The 01a scope never writes
  # `pending_approval` directly, but the column is included on this
  # model so 01b's flip-back transitions are atomic when they ship.
  before_update :stamp_resolved_at_on_resolution

  # Display-friendly truncated fingerprint for the attempt-log table.
  # The full hash is on the row's `show` page. Twelve hex chars keeps
  # the table tight while preserving enough disambiguation for the
  # operator (~48 bits of unique prefix).
  def fingerprint_short
    fingerprint_hash.to_s[0, 12]
  end

  # Compact "city, country (region)" string. Used by the helper +
  # the component; centralized so the format stays consistent across
  # the table row, the show page, and the future notification card.
  def geo_summary
    parts = []
    parts << geo_city if geo_city.present?
    parts << geo_country if geo_country.present?
    label = parts.join(", ")
    label += " (#{geo_region})" if geo_region.present? && parts.any?
    label.presence
  end

  private

  def stamp_resolved_at_on_resolution
    return unless will_save_change_to_result?
    was, now = result_change
    return if was.nil?
    return unless was == "pending_approval" && now != "pending_approval"

    self.resolved_at ||= Time.current
  end

  # Validate that `ip_prefix` family matches `ip` family — a /24 with
  # an IPv6 `ip` would silently mismatch the lookup index, and a /64
  # with an IPv4 `ip` is meaningless. Soft validation: bail on parse
  # failure rather than re-raising so the standard
  # `validates :ip, presence: true` runs first.
  def ip_prefix_family_matches_ip
    return if ip.blank? || ip_prefix.blank?

    ip_addr     = IPAddr.new(ip.to_s)
    prefix_addr = IPAddr.new(ip_prefix.to_s.split("/").first.to_s)

    if ip_addr.ipv4? != prefix_addr.ipv4?
      errors.add(:ip_prefix, "family must match ip")
    end
  rescue IPAddr::Error
    errors.add(:ip_prefix, "is not a valid CIDR")
  end
end
