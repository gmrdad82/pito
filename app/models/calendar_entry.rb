# Phase 15 §1 — Calendar Data Model.
#
# Central calendar entry. Eight `entry_type` values, three `source`
# provenances, four `state` values. Type-specific cross-references live
# as typed FK columns (`video_id`, `game_id`, `channel_id`, `project_id`,
# `parent_entry_id`, `milestone_rule_id`); type-specific data lives in
# `metadata` (jsonb). Validators enforce both shapes.
#
# Read-only enforcement: `derived` and `auto` entries are read-only
# outside `metadata.user_overrides`. The model-level callback rejects
# any attribute write outside the user_overrides sub-key. The
# `Calendar::Derivation` service bypasses by re-driving the upsert
# through a dedicated re-sync code path that calls `assign_attributes`
# from inside the service (the service is the canonical writer).
class CalendarEntry < ApplicationRecord
  belongs_to :video,           optional: true
  belongs_to :game,            optional: true
  belongs_to :channel,         optional: true
  belongs_to :project,         optional: true
  belongs_to :parent_entry,
             class_name: "CalendarEntry",
             optional: true
  belongs_to :milestone_rule,  optional: true
  belongs_to :created_by_user,
             class_name: "User",
             optional: true

  has_many :child_entries,
           class_name: "CalendarEntry",
           foreign_key: :parent_entry_id,
           dependent: :nullify,
           inverse_of: :parent_entry

  enum :entry_type, {
    channel_published: 0,
    video_published:   1,
    video_scheduled:   2,
    game_release:      3,
    purchase_planned:  4,
    milestone_manual:  5,
    milestone_auto:    6,
    custom:            7
  }
  enum :source, { manual: 0, derived: 1, auto: 2 }
  enum :state, {
    scheduled:  0,
    occurred:   1,
    cancelled:  2,
    superseded: 3
  }
  enum :release_precision,
       { day: 0, month: 1, quarter: 2, year: 3, tba: 4 },
       prefix: true

  validates :title,       presence: true, length: { in: 1..255 }
  validates :description, length: { maximum: 5000 }, allow_blank: true
  validates :timezone,    presence: true
  validate  :timezone_must_be_iana
  validate  :ends_at_after_starts_at
  validate  :derived_entries_have_source_ref
  validate  :purchase_planned_has_parent_entry
  validate  :milestone_auto_has_rule

  validates_with CalendarEntryMetadataValidator
  validates_with CalendarEntryCrossReferenceValidator

  before_validation :stamp_install_timezone, on: :create

  # Read-only enforcement: derived / auto entries reject writes to
  # anything except `metadata.user_overrides`. The Calendar::Derivation
  # service bypasses by setting `@bypass_readonly = true` before its
  # `save!`; that flag is process-local on the record instance and is
  # never persisted.
  attr_accessor :bypass_readonly
  before_save :reject_writes_to_derived_outside_user_overrides

  # ──── Scopes ───────────────────────────────────────────────────────

  # Entries whose [starts_at, ends_at) overlaps [a, b).
  # An entry with `ends_at IS NULL` is treated as point-in-time at
  # `starts_at` and is included if `a <= starts_at < b`.
  scope :in_range, ->(start_at, end_at) {
    where(
      "starts_at < :b AND COALESCE(ends_at, starts_at) >= :a",
      a: start_at, b: end_at
    )
  }

  scope :upcoming_releases, -> {
    where(entry_type: :game_release)
      .where("starts_at >= ?", Time.current)
      .order(:starts_at)
  }

  scope :upcoming_releases_without_purchase, -> {
    upcoming_releases
      .where.not(
        id: where(entry_type: :purchase_planned)
              .select(:parent_entry_id)
      )
  }

  scope :recent_milestones, ->(window: 30.days) {
    where(entry_type: %i[milestone_manual milestone_auto])
      .where(starts_at: window.ago..Time.current)
  }

  # Default visibility: hide cancelled and superseded entries unless
  # the caller opts in. Used by views to honor the master-decision rule
  # ("hide :cancelled and :superseded by default").
  scope :visible, -> {
    where.not(state: %i[cancelled superseded])
  }

  # ──── Predicates ───────────────────────────────────────────────────

  def derived_or_auto?
    derived? || auto?
  end

  def read_only?
    derived_or_auto?
  end

  private

  def timezone_must_be_iana
    return if timezone.blank?
    return if ActiveSupport::TimeZone[timezone].present?
    errors.add(:timezone, "is not a valid IANA timezone")
  end

  def ends_at_after_starts_at
    return if ends_at.nil? || starts_at.nil?
    return if ends_at >= starts_at
    errors.add(:ends_at, "must be after or equal to starts_at")
  end

  def derived_entries_have_source_ref
    return unless derived_or_auto?
    return if source_ref.present?
    errors.add(:source_ref, "is required for derived / auto entries")
  end

  def purchase_planned_has_parent_entry
    return unless purchase_planned?
    return if parent_entry_id.present?
    errors.add(:parent_entry_id, "is required for purchase_planned entries")
  end

  def milestone_auto_has_rule
    return unless milestone_auto?
    return if milestone_rule_id.present?
    errors.add(:milestone_rule_id, "is required for milestone_auto entries")
  end

  def stamp_install_timezone
    return if timezone.present?
    self.timezone = AppSetting.first&.timezone || "UTC"
  end

  def reject_writes_to_derived_outside_user_overrides
    return unless derived_or_auto?
    return if new_record?
    return if bypass_readonly

    forbidden_changes = changes.keys - %w[updated_at metadata]
    return if forbidden_changes.empty? && metadata_changes_only_user_overrides?

    if !forbidden_changes.empty? || !metadata_changes_only_user_overrides?
      errors.add(:base,
                 "derived / auto entries are read-only outside metadata.user_overrides")
      throw(:abort)
    end
  end

  def metadata_changes_only_user_overrides?
    return true unless metadata_changed?
    before, after = changes["metadata"]
    before_without_overrides = (before || {}).except("user_overrides")
    after_without_overrides  = (after  || {}).except("user_overrides")
    before_without_overrides == after_without_overrides
  end
end
