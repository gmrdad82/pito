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

  # Rails 8.1 — defensive: lock the enum-backing column types.
  attribute :kind, :integer
  attribute :severity, :integer

  enum :kind, {
    video_published: 0,
    # DEPRECATED 2026-05-12 — kind retained for enum-integer stability
    # so future kinds don't collide on `1`. Emission paths, formatter
    # templates, and source helpers were removed in the same patch.
    # See `db/migrate/20260512010000_drop_deprecated_notification_kinds.rb`.
    video_pre_publish_check_missed: 1,
    # DEPRECATED 2026-05-12 — pre-release reminder track dropped per
    # user direction (one notification per game release, not two).
    # `game_release_today` (kind 3) is the sole survivor. Enum value
    # retained for integer stability.
    game_release_upcoming: 2,
    game_release_today: 3,
    milestone_reached: 4,
    calendar_entry_firing: 5,
    sync_error: 6,
    youtube_reauth_needed: 7,
    # Phase 22 — `[import]` modal completion notification. One row per
    # ImportJob transition into a terminal state (completed OR failed);
    # the severity column distinguishes them (`success` vs `warn`).
    import_job_completed: 8,
    # Phase 23 §23d — emitted by `VideoDiffCheckJob` when a video's
    # YouTube state has diverged from Pito's. The user resolves the
    # diff field-by-field at `/videos/:slug/diff`. Severity `info` —
    # not urgent, not destructive, just "you have something to look
    # at".
    video_diff_detected: 9,
    # REMOVED (Unit A0, beta-2) — `channel_diff_detected` (kind 10).
    # The channel diff-reconciliation surface was cut when the channel
    # became a strictly read-only mirror; the emitting job and the
    # formatter template were deleted in the same change. Kind value
    # 10 is intentionally left unused so future kinds don't collide.
    # Phase 25 — 01c. Emitted by `NotificationSource::LoginPendingApproval`
    # when a new-location correct-password login waits for approval.
    # Severity is `urgent`. Dedupe key is
    # `"login-pending-#{login_attempt_id}"` so re-runs collapse to a
    # single row per pending attempt.
    login_pending_approval: 11
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

  # Phase 16 §3 — Turbo Stream broadcasts for the live unread badge
  # and the index live-prepend. Two streams:
  #
  #   - "notifications_badge" — replace the badge fragment on every
  #     insert + every read-state change. Frontend renders the partial
  #     under a stable `dom_id "notifications_badge"`. The partial
  #     emits an empty span when `unread_count == 0`, so flipping the
  #     last unread row read disappears the badge in place.
  #   - "notifications_index" — prepend new rows so an open index page
  #     surfaces them without a manual reload, AND replace the row's
  #     `dom_id(self)` partial on update so a "mark read" performed in
  #     another session updates the row's bold/muted styling live.
  #
  # The broadcasts use the `*_later_to` variants for inserts (defer to
  # an ActiveJob enqueue) so the request-cycle that creates the row
  # returns quickly. Read-state changes use the immediate variant — the
  # user is waiting for the badge to decrement.
  after_create_commit :broadcast_index_prepend
  after_create_commit :broadcast_badge_after_create
  after_update_commit :broadcast_badge_after_update
  after_update_commit :broadcast_row_replace_after_update
  after_destroy_commit :broadcast_badge_after_destroy

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

  def broadcast_index_prepend
    Turbo::StreamsChannel.broadcast_prepend_later_to(
      "notifications_index",
      target: "notifications_list",
      partial: "notifications/notification",
      locals: { notification: self }
    )
  rescue StandardError => e
    Rails.logger.warn("Notification##{id}: broadcast_index_prepend failed: #{e.class}: #{e.message}")
  end

  def broadcast_badge_after_create
    broadcast_badge
  end

  def broadcast_badge_after_update
    return unless saved_change_to_in_app_read_at?

    broadcast_badge
    broadcast_row_replace
  end

  def broadcast_row_replace_after_update
    # Row replace is also handled inside broadcast_badge_after_update
    # for read-state flips. Skip the no-op duplicate here unless the
    # title / body / severity changed via a re-template.
    return if saved_change_to_in_app_read_at?
    return unless saved_change_to_title? ||
                  saved_change_to_body? ||
                  saved_change_to_severity? ||
                  saved_change_to_url?

    broadcast_row_replace
  end

  def broadcast_badge_after_destroy
    broadcast_badge
  end

  def broadcast_badge
    Turbo::StreamsChannel.broadcast_replace_to(
      "notifications_badge",
      target: "notifications_badge",
      partial: "notifications/badge",
      locals: { unread_count: self.class.unread.count }
    )
  rescue StandardError => e
    Rails.logger.warn("Notification##{id}: broadcast_badge failed: #{e.class}: #{e.message}")
  end

  def broadcast_row_replace
    Turbo::StreamsChannel.broadcast_replace_to(
      "notifications_index",
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "notifications/notification",
      locals: { notification: self }
    )
  rescue StandardError => e
    Rails.logger.warn("Notification##{id}: broadcast_row_replace failed: #{e.class}: #{e.message}")
  end

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
