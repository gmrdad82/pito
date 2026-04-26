class BulkOperation < ApplicationRecord
  has_many :bulk_operation_items, dependent: :destroy
  has_many :videos, through: :bulk_operation_items

  enum :kind, { update_metadata: 0, update_privacy: 1, add_to_playlist: 2, remove_from_playlist: 3 }
  enum :status, { pending: 0, running: 1, completed: 2, failed: 3 }, prefix: true

  validates :kind, presence: true
end
