# Phase 7.5 §11a (Channel Schema + Sync Foundation).
#
# Append-only audit row recording one push of a rate-limited Channel
# field (title or handle). Created exclusively by the (future) 11c
# edit-path service after a successful YouTube `channels.update` call.
#
# Append-only enforcement: persisted rows are read-only at the model
# layer (`readonly?` returns true once `persisted?` is true), so
# `update!` / `destroy` raise `ActiveRecord::ReadOnlyRecord`. New rows
# can still be created normally. The DB does NOT carry a trigger; the
# constraint lives in code so future direct SQL inserts (e.g. import
# from another pito install) stay possible without DB-side
# coordination.
class ChannelChangeLog < ApplicationRecord
  FIELDS = %w[title handle].freeze

  belongs_to :channel
  belongs_to :changed_by_user, class_name: "User"

  validates :field, presence: true, inclusion: { in: FIELDS }
  validates :new_value, presence: true
  validates :changed_at, presence: true

  scope :recent, -> { order(changed_at: :desc).limit(20) }

  # Persisted rows are read-only. New (unpersisted) records remain
  # writable until the first `save!` so the create path is unaffected.
  def readonly?
    persisted?
  end
end
