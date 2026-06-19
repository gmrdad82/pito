# Cross-reference shape validator.
#
# Each `entry_type` declares which typed FKs are required, allowed, or
# forbidden. The model layer rejects mismatched shapes so the database
# is never asked to enforce them.
#
# D18 (2026-05-21) — Projects dropped; `project_id` removed from every
# rule's allowed list.
class CalendarEntryCrossReferenceValidator < ActiveModel::Validator
  # Per-type rule table:
  #   - required: list of FK columns that MUST be set.
  #   - allowed:  list of FK columns that MAY be set.
  #   - forbidden: list of FK columns that MUST be nil.
  RULES = {
    "channel_published" => {
      required:  [],
      allowed:   %i[channel_id],
      forbidden: %i[video_id game_id parent_entry_id milestone_rule_id]
    },
    "video_published" => {
      required:  %i[video_id],
      allowed:   [],
      forbidden: %i[game_id channel_id parent_entry_id milestone_rule_id]
    },
    "video_scheduled" => {
      required:  %i[video_id],
      allowed:   [],
      forbidden: %i[game_id channel_id parent_entry_id milestone_rule_id]
    },
    "game_release" => {
      required:  [],
      allowed:   %i[game_id],
      forbidden: %i[video_id channel_id parent_entry_id milestone_rule_id]
    },
    "purchase_planned" => {
      required:  %i[parent_entry_id],
      allowed:   %i[game_id],
      forbidden: %i[video_id channel_id milestone_rule_id]
    },
    "milestone_manual" => {
      required:  [],
      allowed:   [],
      forbidden: %i[video_id channel_id game_id parent_entry_id milestone_rule_id]
    },
    "milestone_auto" => {
      required:  %i[milestone_rule_id],
      allowed:   [],
      forbidden: %i[video_id channel_id game_id parent_entry_id]
    },
    "custom" => {
      required:  [],
      allowed:   [],
      forbidden: %i[video_id channel_id game_id parent_entry_id milestone_rule_id]
    }
  }.freeze

  def validate(record)
    return if record.entry_type.blank?

    rules = RULES[record.entry_type]
    return unless rules

    rules[:required].each do |fk|
      next if record.public_send(fk).present?
      record.errors.add(fk, "is required for #{record.entry_type} entries")
    end

    rules[:forbidden].each do |fk|
      next if record.public_send(fk).blank?
      record.errors.add(fk, "must be blank for #{record.entry_type} entries")
    end
  end
end
