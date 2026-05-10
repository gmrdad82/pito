# Phase 15 §1 — Calendar Data Model.
#
# Declarative rule. The MilestoneEvaluator iterates enabled, never-fired
# rules and writes a `milestone_auto` calendar entry when the metric
# crosses the threshold per `direction`. Idempotent firing via the
# `fired_at IS NULL` predicate. Re-arming requires explicit clearing.
class MilestoneRule < ApplicationRecord
  belongs_to :created_by_user,
             class_name: "User",
             optional: true

  has_many :calendar_entries,
           dependent: :nullify,
           inverse_of: :milestone_rule

  # Note 5's `tenant` scope is renamed `install` per ADR 0003 (single-
  # install posture; no Tenant model). The integer-backed enum value
  # 0 stays the same.
  enum :scope_type, { install: 0, channel: 1, video: 2 }
  # Phase 13's analytics enum uses short-form window names (`7d`, `28d`,
  # `90d`, `lifetime`); we mirror those here. Integer values follow the
  # spec: lifetime=0, seven_day=1, twentyeight_day=2, ninety_day=3, but
  # the public API name maps to the short form for cross-phase
  # consistency.
  enum :metric_window, {
    lifetime:        0,
    "7d":            1,
    "28d":           2,
    "90d":           3
  }
  enum :direction, { cross_up: 0, cross_down: 1 }

  validates :name,      presence: true, length: { in: 1..255 }
  validates :metric,    presence: true, length: { maximum: 255 }
  validates :threshold, numericality: true
  validate  :scope_id_presence_matches_scope_type
  validate  :scope_id_references_valid_target

  # Fire the rule: write a `milestone_auto` calendar entry and stamp
  # `fired_at`. Both writes happen in a single transaction so a failure
  # in either rolls back both. Raises on a second call (idempotency
  # check). Re-arm via `re_arm!` to clear `fired_at`.
  def fire!(metric_value:, fired_at: Time.current)
    raise "already fired" if self.fired_at.present?

    transaction do
      update!(fired_at: fired_at)

      tz = AppSetting.first&.timezone || "UTC"
      CalendarEntry.create!(
        entry_type: :milestone_auto,
        source: :auto,
        state: :occurred,
        title: name,
        starts_at: fired_at,
        all_day: false,
        timezone: tz,
        milestone_rule_id: id,
        source_ref: { milestone_rule_id: id,
                      metric_value_at_fire: metric_value },
        metadata: { metric_value_at_fire: metric_value,
                    user_overrides: {} }
      )
    end
  end

  def re_arm!
    update!(fired_at: nil)
  end

  private

  def scope_id_presence_matches_scope_type
    if install? && scope_id.present?
      errors.add(:scope_id, "must be blank for install scope")
    elsif !install? && scope_id.blank?
      errors.add(:scope_id, "is required for #{scope_type} scope")
    end
  end

  def scope_id_references_valid_target
    return if install?
    return if scope_id.blank?

    klass = channel? ? Channel : Video
    return if klass.exists?(id: scope_id)
    errors.add(:scope_id,
               "does not reference an existing #{scope_type}")
  end
end
