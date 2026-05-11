# Phase 11 §01a — Video edit page polish. End-screens live in a
# dedicated table; render order is `position ASC`. Up to 4 non-`none`
# rows per video, OR a single `kind: none` row marking "no end-screen
# needed" (locked decision §5 in the parent plan).
#
# Target ID + label are free-text in v1 — YouTube-side validation is
# parent open question §6 and is deferred. Empty target rows for
# `kind: none` are allowed.
class VideoEndScreen < ApplicationRecord
  belongs_to :video

  attribute :kind, :integer
  enum :kind,
       { related_video: 0, related_channel: 1, related_playlist: 2, none: 3 },
       prefix: :kind

  validates :kind, presence: true
  validates :target_label, length: { maximum: 100 }, allow_blank: true
  validate :target_id_required_unless_none
  validate :no_extra_rows_when_kind_none
  validate :max_four_non_none_rows_per_video

  scope :ordered, -> { order(:position, :id) }

  private

  # `kind: related_video / related_channel / related_playlist` needs
  # a `target_id`. `kind: none` is the explicit "skip end-screen" row;
  # both fields stay blank.
  def target_id_required_unless_none
    return if kind_none?
    return if target_id.to_s.strip.present?
    errors.add(:target_id, "is required for #{kind} end-screens")
  end

  # If THIS row is `kind: none`, no other row for the same video may
  # exist after save. Per-row guard catches direct-AR / MCP creates.
  # When the parent is saving us through nested attributes,
  # `Video#end_screens_invariants` handles the in-memory case (it
  # respects `marked_for_destruction?`); we skip the DB query here
  # in that case so we don't false-trigger on rows the parent is
  # about to destroy in the same transaction.
  def no_extra_rows_when_kind_none
    return unless kind_none?
    return unless video_id
    return if parent_is_saving_via_nested_attributes?
    other = VideoEndScreen.where(video_id: video_id).where.not(id: id)
    return if other.empty?
    errors.add(:base, "cannot mix a 'none' end-screen with other rows")
  end

  # YouTube caps the end-screen at 4 elements. Per-row guard catches
  # direct-AR / MCP creates; parent-driven nested-attribute saves
  # defer to `Video#end_screens_invariants`.
  def max_four_non_none_rows_per_video
    return if kind_none?
    return unless video_id
    return if parent_is_saving_via_nested_attributes?
    siblings = VideoEndScreen.where(video_id: video_id)
                              .where.not(id: id)
                              .where.not(kind: self.class.kinds[:none])
    return if siblings.count < 4
    errors.add(:base, "no more than 4 non-none end-screens per video")
  end

  # When the parent video is saving us through nested attributes,
  # the in-memory `video_end_screens` association contains rows
  # marked for destruction or freshly built that the per-row
  # DB-query checks can't see. Defer in that case — the parent's
  # `end_screens_invariants` validator runs against the in-memory
  # collection and catches actual violations.
  #
  # `target` returns the in-memory array regardless of `loaded?`
  # state, which is what we need: the assignment from nested
  # attributes populates target but does not always flip `loaded?`.
  def parent_is_saving_via_nested_attributes?
    return false unless video
    target = video.association(:video_end_screens).target
    target.any? { |r| r.marked_for_destruction? || r.new_record? }
  end
end
