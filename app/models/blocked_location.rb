# Phase 25 — 01a (LD-10). Auto-block list. The 01a sub-spec creates
# the schema, the validations, the scopes, and one helper
# (`for_pair?`) the `Auth::AttemptLogger` reads on every authenticate
# POST. Actual block creation lives in 01d (MCP / web `block this
# attempt` action) and 01f (auto-block sweep + web purge surface).
#
# Soft-unblock: setting `unblocked_at` flips the row out of `active`
# but preserves the audit history. `for_pair?` consults only active
# rows.
#
# `source_surface` records which surface issued the block:
#
#   - `web` — `/login_attempts/:id/block` action page
#   - `tui` — in-TUI overlay
#   - `mcp` — `login_attempt_block` MCP tool
class BlockedLocation < ApplicationRecord
  belongs_to :blocked_by_user,
             class_name: "User",
             foreign_key: :blocked_by_user_id
  belongs_to :unblocked_by_user,
             class_name: "User",
             foreign_key: :unblocked_by_user_id,
             optional: true

  enum :source_surface, {
    web: 0,
    tui: 1,
    mcp: 2
  }, prefix: :source

  validates :fingerprint_hash, presence: true, length: { is: 64 }
  validates :ip_prefix, presence: true
  validates :blocked_at, presence: true
  validates :blocked_by_user_id, presence: true
  validate  :ip_prefix_is_valid_cidr

  before_validation :default_blocked_at, on: :create

  scope :active, -> { where(unblocked_at: nil) }
  scope :for_pair,
        ->(fp, ip_prefix) {
          where(fingerprint_hash: fp, ip_prefix: ip_prefix)
        }

  def self.for_pair?(fp, ip_prefix)
    return false if fp.blank? || ip_prefix.blank?
    active.for_pair(fp, ip_prefix).exists?
  end

  # Bump the activity counter on a matched-but-rejected attempt. Used
  # by `Auth::AttemptLogger` when an attempt is short-circuited by an
  # active block.
  def self.bump_attempt!(fp, ip_prefix)
    return if fp.blank? || ip_prefix.blank?
    row = active.for_pair(fp, ip_prefix).first
    return unless row
    row.update!(
      attempt_count: row.attempt_count.to_i + 1,
      last_attempt_at: Time.current
    )
  end

  def active?
    unblocked_at.nil?
  end

  private

  def default_blocked_at
    self.blocked_at ||= Time.current
  end

  def ip_prefix_is_valid_cidr
    return if ip_prefix.blank?
    IPAddr.new(ip_prefix.to_s)
  rescue IPAddr::Error
    errors.add(:ip_prefix, "is not a valid CIDR")
  end
end
