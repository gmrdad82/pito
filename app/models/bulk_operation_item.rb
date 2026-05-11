class BulkOperationItem < ApplicationRecord
  belongs_to :bulk_operation
  belongs_to :video, optional: true
  belongs_to :target, polymorphic: true, optional: true

  # Rails 8.1 — defensive: lock the enum-backing column type.
  attribute :status, :integer
  enum :status, { pending: 0, succeeded: 1, failed: 2, skipped: 3 }, prefix: true

  validates :target_type, presence: true
  validates :target_id, presence: true
end
