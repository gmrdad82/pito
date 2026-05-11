# Phase 25 — 01a (LD-5). Trusted location list. Schema-only here; the
# upsert on a successful login lives in 01b's new-location detection
# pipeline, and 01b also adds the `User#trusted?(fp, ip_prefix)`
# convenience method.
#
# Composite unique key on (user_id, fingerprint_hash, ip_prefix) is
# enforced at the DB level. Model-level uniqueness validation is
# scoped to the same triple so a `valid?` call surfaces the conflict
# before the DB raises.
#
# `first_seen_at` is set on insert; `last_seen_at` is bumped each time
# the user re-authenticates from the same pair. Both stamps are
# nullable in the validator path but the schema declares NOT NULL so
# 01b's writer must always set them explicitly.
class TrustedLocation < ApplicationRecord
  belongs_to :user

  validates :user_id, presence: true
  validates :fingerprint_hash, presence: true, length: { is: 64 }
  validates :ip_prefix, presence: true
  validates :first_seen_at, presence: true
  validates :last_seen_at, presence: true
  validates :fingerprint_hash,
            uniqueness: { scope: [ :user_id, :ip_prefix ] },
            on: :create
  validate :ip_prefix_is_valid_cidr

  scope :for_user, ->(user) { where(user_id: user&.id) }
  scope :for_pair,
        ->(fp, ip_prefix) {
          where(fingerprint_hash: fp, ip_prefix: ip_prefix)
        }

  def self.trusted?(user, fp, ip_prefix)
    return false if user.nil? || fp.blank? || ip_prefix.blank?
    for_user(user).for_pair(fp, ip_prefix).exists?
  end

  private

  def ip_prefix_is_valid_cidr
    return if ip_prefix.blank?
    IPAddr.new(ip_prefix.to_s)
  rescue IPAddr::Error
    errors.add(:ip_prefix, "is not a valid CIDR")
  end
end
