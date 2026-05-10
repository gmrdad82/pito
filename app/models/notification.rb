# Phase 16 §1 — Notifications data model + delivery channels.
#
# Central notification row. Single shared inbox per Q1
# (`docs/plans/beta/16-notifications/specs/01-notification-data-model-and-delivery.md`):
# any logged-in user sees every row; marking-read marks for everyone.
#
# Idempotency keys: every row must carry either a `source_calendar_entry_id`
# (for calendar-derived rows) OR a `dedup_key` (for non-calendar event
# sources). Two unique partial indexes serialize concurrent inserts.
#
# Delivery state lives in three nullable timestamp columns:
#
# - `in_app_read_at` — NULL = unread; non-NULL = read by some user.
#   The "in-app delivery" itself is the row's existence; `created_at`
#   doubles as `in_app_delivered_at`.
# - `discord_delivered_at` — stamped by `NotificationDeliveryChannel::Discord`
#   on a successful webhook POST.
# - `slack_delivered_at` — stamped by `NotificationDeliveryChannel::Slack`
#   on a successful webhook POST.
#
# Single shared `retry_count` per row (Q11 + master decision 2026-05-10
# #3). Per-channel counters are a follow-up if needed.
class Notification < ApplicationRecord
  # Reject app-path values containing whitespace (we accept absolute
  # http(s) URLs OR leading-slash app paths only — master decision #7).
  #
  # The APP_PATH_PATTERN explicitly forbids a second `/` or `\` as the
  # second character so protocol-relative URLs (`//evil.com/path`) and
  # backslash-bypass variants (`/\evil.com/x`) cannot smuggle an
  # external host past the validator (open-redirect class). Interior
  # double-slashes (`/foo//bar`) are still allowed.
  ABSOLUTE_URL_PATTERN = %r{\Ahttps?://[^\s]+\z}
  APP_PATH_PATTERN     = %r{\A/(?![/\\])[^\s]*\z}

  belongs_to :source_calendar_entry,
             class_name: "CalendarEntry",
             optional: true
  belongs_to :source_milestone_rule,
             class_name: "MilestoneRule",
             optional: true
  belongs_to :created_by_user,
             class_name: "User",
             optional: true

  enum :kind, {
    video_published: 0,
    video_pre_publish_check_missed: 1,
    game_release_upcoming: 2,
    game_release_today: 3,
    milestone_reached: 4,
    calendar_entry_firing: 5,
    sync_error: 6,
    youtube_reauth_needed: 7
  }
  enum :severity, { info: 0, success: 1, warn: 2, urgent: 3 }

  validates :event_type, presence: true,
                         length: { in: 1..64 }
  validates :title, presence: true,
                    length: { in: 1..255 }
  validates :body, length: { maximum: 5000 }, allow_nil: true
  validates :url, length: { maximum: 1000 }, allow_nil: true
  validates :fires_at, presence: true
  validates :last_error, length: { maximum: 1000 }, allow_nil: true
  validate :url_is_well_formed_when_present
  validate :idempotency_keys_present

  scope :unread, -> { where(in_app_read_at: nil) }
  scope :read,   -> { where.not(in_app_read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_kind, ->(k) { where(kind: k) }
  scope :ripe_for_delivery, -> { where("fires_at <= ?", Time.current) }
  scope :pending_discord, -> { where(discord_delivered_at: nil) }
  scope :pending_slack,   -> { where(slack_delivered_at: nil) }

  def mark_read!(at: Time.current)
    update!(in_app_read_at: at)
  end

  def mark_unread!
    update!(in_app_read_at: nil)
  end

  def read?
    in_app_read_at.present?
  end

  def unread?
    !read?
  end

  private

  def url_is_well_formed_when_present
    return if url.blank?
    return if url.match?(ABSOLUTE_URL_PATTERN) || url.match?(APP_PATH_PATTERN)

    errors.add(:url, "must be an absolute http(s) URL or a leading-slash app path")
  end

  def idempotency_keys_present
    return if source_calendar_entry_id.present? || dedup_key.present?

    errors.add(:base,
               "must carry either source_calendar_entry_id or dedup_key")
  end
end
