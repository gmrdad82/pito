class BulkOperationItem < ApplicationRecord
  belongs_to :bulk_operation
  belongs_to :video

  enum :status, { pending: 0, succeeded: 1, failed: 2 }, prefix: true

  validates :video_id, uniqueness: { scope: :bulk_operation_id }
end
