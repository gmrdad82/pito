class BulkOperation < ApplicationRecord
  include Turbo::Broadcastable
  include BelongsToTenant

  has_many :bulk_operation_items, dependent: :destroy
  has_many :videos, through: :bulk_operation_items

  enum :kind, { update_metadata: 0, update_privacy: 1, add_to_playlist: 2, remove_from_playlist: 3, bulk_delete: 4, bulk_sync: 5 }
  enum :status, { pending: 0, running: 1, completed: 2, failed: 3 }, prefix: true

  validates :kind, presence: true

  def target_count
    bulk_operation_items.count
  end

  def succeeded_count
    bulk_operation_items.status_succeeded.count
  end

  def failed_count
    bulk_operation_items.status_failed.count
  end

  def progress_percent
    return 0 if target_count.zero?
    ((succeeded_count + failed_count).to_f / target_count * 100).round(0)
  end
end
