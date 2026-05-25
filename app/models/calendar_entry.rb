# Phase 15 §1 — Calendar Data Model.
#
# Central calendar entry. Thirteen `entry_type` values grouped into five
# high-level `category` values (derived — no stored column). Three
# `source` provenances, four `state` values. Type-specific
# cross-references live as typed FK columns (`video_id`, `game_id`,
# `channel_id`, `parent_entry_id`, `milestone_rule_id`); type-specific
# data lives in `metadata` (jsonb). Validators enforce both shapes.
#
# D18 (2026-05-21) — Projects dropped; `project_id` column + relation
# removed alongside the Project model.
#
# Category mapping (B5, 2026-05-25) — derived from `entry_type` via
# `#category`; no stored column. Call `CalendarEntry.in_category(cat)`
# for a scope-compatible query.
#
#   :channel  ← channel_published, video_published, video_scheduled,
#                channel_anniversary, channel_metadata_change,
#                channel_milestone
#   :game     ← game_release, purchase_planned, owned_release_imminent
#   :system   ← system_event, milestone_auto (legacy compat)
#   :manual   ← milestone_manual, custom
#
# `milestone_auto` (integer 6) is kept in the enum for backwards
# compatibility with existing rows; it routes to `:system` if present.
#
# Read-only enforcement: `derived` and `auto` entries are read-only
# outside `metadata.user_overrides`. The model-level callback rejects
# any attribute write outside the user_overrides sub-key. The
# `Pito::Calendar::Derivation` service bypasses by re-driving the upsert
# through a dedicated re-sync code path that calls `assign_attributes`
# from inside the service (the service is the canonical writer).
class CalendarEntry < ApplicationRecord
  belongs_to :video,           optional: true
  belongs_to :game,            optional: true
  belongs_to :channel,         optional: true
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

  # Rails 8.1 — defensive: lock the enum-backing column types.
  attribute :entry_type, :integer
  attribute :source, :integer
  attribute :state, :integer
  attribute :release_precision, :integer

  enum :entry_type, {
    channel_published:       0,
    video_published:         1,
    video_scheduled:         2,
    game_release:            3,
    purchase_planned:        4,
    milestone_manual:        5,
    milestone_auto:          6,  # legacy — routes to :system category
    custom:                  7,
    # B5 (2026-05-25) — new entry types.
    channel_anniversary:     8,  # year anniversary for a channel
    channel_metadata_change: 9,  # title / description / branding change
    channel_milestone:       10, # sub count / view count milestone
    owned_release_imminent:  11, # owned game releasing within N days
    system_event:            12  # infrastructure events (Sidekiq retries, storage warnings, log truncation)
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
  # anything except `metadata.user_overrides`. Service / controller code
  # opts specific attributes out of the check by setting
  # `bypass_readonly_for` to an Array of attribute names (Symbols or
  # Strings) before `save!`. The flag is process-local on the record
  # instance and is never persisted.
  #
  # Whole-record bypass was removed in Phase 15 security audit F1: a
  # blanket `bypass_readonly = true` short-circuit lets any other
  # attribute on the record sneak through if a caller forgets to
  # restrict the change set. The scoped allowlist forces every bypass
  # site to be explicit about which attributes it intends to mutate.
  attr_accessor :bypass_readonly_for
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

  # ──── Category ─────────────────────────────────────────────────────
  #
  # Five high-level categories derived from `entry_type`. Stored nowhere;
  # always computed. Use `in_category` scope for DB-level filtering.

  # Maps each entry_type symbol to its category symbol. The map is
  # intentionally exhaustive so any newly added entry_type value raises
  # KeyError at call time rather than silently returning nil.
  ENTRY_TYPE_CATEGORY = {
    channel_published:       :channel,
    video_published:         :channel,
    video_scheduled:         :channel,
    channel_anniversary:     :channel,
    channel_metadata_change: :channel,
    channel_milestone:       :channel,
    game_release:            :game,
    purchase_planned:        :game,
    owned_release_imminent:  :game,
    milestone_manual:        :manual,
    custom:                  :manual,
    milestone_auto:          :system,
    system_event:            :system
  }.freeze

  # Returns the category symbol for this entry: :channel, :game,
  # :system, or :manual. Raises KeyError if the entry_type value is
  # unrecognised (signals a mapping gap, not a nil fallback).
  def category
    ENTRY_TYPE_CATEGORY.fetch(entry_type.to_sym)
  end

  # Returns all entry_type integer values that belong to `cat`.
  # Used internally by `in_category` to build the SQL IN list without
  # round-tripping through Ruby object instantiation.
  def self.entry_types_for_category(cat)
    symbols = ENTRY_TYPE_CATEGORY.select { |_, v| v == cat.to_sym }.keys
    raise ArgumentError, "Unknown category #{cat.inspect}" if symbols.empty?

    symbols.map { |sym| entry_types[sym] }
  end

  # Scope: entries whose entry_type falls within the given category.
  # Accepts :channel, :game, :system, :manual (or string equivalents).
  #
  # Example:
  #   CalendarEntry.in_category(:game).in_range(Date.today, 30.days.from_now)
  scope :in_category, lambda { |cat|
    where(entry_type: entry_types_for_category(cat))
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
    self.timezone = Rails.application.config.x.pito.timezone
  end

  def reject_writes_to_derived_outside_user_overrides
    return unless derived_or_auto?
    return if new_record?

    allowlist = Array(bypass_readonly_for).map(&:to_s)
    forbidden_changes = changes.keys - %w[updated_at metadata] - allowlist

    metadata_ok =
      if allowlist.include?("metadata")
        true
      else
        metadata_changes_only_user_overrides?
      end

    return if forbidden_changes.empty? && metadata_ok

    errors.add(:base,
               "derived / auto entries are read-only outside metadata.user_overrides")
    throw(:abort)
  end

  def metadata_changes_only_user_overrides?
    return true unless metadata_changed?
    before, after = changes["metadata"]
    before_without_overrides = (before || {}).except("user_overrides")
    after_without_overrides  = (after  || {}).except("user_overrides")
    before_without_overrides == after_without_overrides
  end
end
