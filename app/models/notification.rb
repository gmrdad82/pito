# frozen_string_literal: true

class Notification < ApplicationRecord
  LEVELS = %w[info success warning error].freeze

  validates :message, presence: true
  validates :level, inclusion: { in: LEVELS }

  # Fan the message out to any configured outbound webhooks (Slack, Discord)
  # once the row is committed. Delivery is isolated per platform in the job.
  after_create_commit { NotificationWebhookDeliverJob.perform_later(id) }

  # Push the refreshed unread count to every open window the moment a
  # notification lands, so the mini-status badge updates without a refresh
  # (read/unread toggles already broadcast from NotificationsController). This
  # is a global-UI sync via the sanctioned Broadcaster, not a scrollback event;
  # the broadcast rescues internally, so a creation never fails on a cable hiccup.
  after_create_commit { Pito::Stream::Broadcaster.broadcast_global_mini_status }

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
