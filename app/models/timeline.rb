# Phase 4 §3.6 + §11.1 — Timeline tracks DaVinci-side editing state per
# project. The aasm machine (editing → exported → uploaded) is linear: no
# skipping, no rewind. The `upload!` transition is the moment a YouTube
# Video record gets created/linked (caller passes the URL; wiring lives in
# Phase B's controller layer).
class Timeline < ApplicationRecord
  include AASM
  include BelongsToTenant

  belongs_to :project, counter_cache: true
  belongs_to :video, optional: true

  validates :title, presence: true, length: { maximum: 255 }

  attribute :title, :string, default: "Untitled timeline"

  enum :state, { editing: 0, exported: 1, uploaded: 2 }

  aasm column: :state, enum: true do
    state :editing, initial: true
    state :exported
    state :uploaded

    event :export do
      transitions from: :editing, to: :exported
    end

    event :upload do
      transitions from: :exported, to: :uploaded
    end
  end
end
