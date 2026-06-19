# frozen_string_literal: true

class Notification < ApplicationRecord
  validates :message, presence: true

  # Fan the message out to any configured outbound webhooks (Slack, Discord)
  # once the row is committed. Delivery is isolated per platform in the job.
  after_create_commit { NotificationWebhookDeliverJob.perform_later(id) }

  scope :unread,  -> { where(read_at: nil) }
  scope :recent,  -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def unread?
    !read?
  end

  def mark_read!
    update!(read_at: Time.current)
  end

  def mark_unread!
    update!(read_at: nil)
  end
end
