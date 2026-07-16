# frozen_string_literal: true

class Notification < ApplicationRecord
  LEVELS = %w[info success warning error shiny].freeze

  # Sidebar panel page size — the panel loads this many rows, then fetches more
  # via keyset pagination (see panel_after / Pito::ListCursor).
  PAGE_SIZE = 50

  validates :message, presence: true
  validates :level, inclusion: { in: LEVELS }

  # Transient (non-persisted) escape hatch for callers that create many
  # Notification rows in one batch (e.g. a scheduled digest job) and want to
  # send ONE combined digest webhook themselves instead of N individual
  # per-record ones. Default (unset/false) leaves today's behavior untouched.
  attr_accessor :skip_webhook

  # Fan the message out to any configured outbound webhooks (Slack, Discord)
  # once the row is committed. Delivery is isolated per platform in the job.
  # Suppressed when skip_webhook is set (see attr_accessor above).
  after_create_commit { NotificationWebhookDeliverJob.perform_later(id) unless skip_webhook }

  # Push the refreshed unread count to every open window the moment a
  # notification lands, so the mini-status badge updates without a refresh
  # (read/unread toggles already broadcast from NotificationsController). This
  # is a global-UI sync via the sanctioned Broadcaster, not a scrollback event;
  # the broadcast rescues internally, so a creation never fails on a cable hiccup.
  after_create_commit { Pito::Stream::Broadcaster.broadcast_global_mini_status }

  scope :unread,        -> { where(read_at: nil) }
  scope :recent,        -> { order(created_at: :desc) }
  # Panel ordering: unread rows first, then read — each group newest-first. The
  # trailing `id DESC` is the STABLE tiebreak that makes keyset pagination
  # correct when many rows share a created_at (e.g. a same-second batch) —
  # without it panel_after could skip or repeat rows across pages.
  scope :panel_ordered, -> { order(Arel.sql("(read_at IS NULL) DESC, created_at DESC, id DESC")) }

  # Keyset "next page" in panel_ordered order, strictly AFTER the cursor row.
  # The cursor is the last row already shown, described by its ordering keys:
  #   read_bucket — 1 if that row was unread (read_at IS NULL), else 0
  #   created_at  — its full-precision timestamp
  #   id          — its id (the stable tiebreak)
  # "After" in a DESC ordering means the row's (bucket, created_at, id) tuple is
  # lexicographically LESS than the cursor's.
  scope :panel_after, ->(read_bucket:, created_at:, id:) {
    bucket = "(read_at IS NULL)::int"
    panel_ordered.where(
      Arel.sql(
        "(#{bucket} < :b) OR " \
        "(#{bucket} = :b AND created_at < :t) OR " \
        "(#{bucket} = :b AND created_at = :t AND id < :i)"
      ),
      b: read_bucket, t: created_at, i: id
    )
  }

  # One page of panel rows in panel_ordered order, plus the OPAQUE cursor token
  # for the next page (nil when this is the last page). `after` is the cursor
  # token of the previous page's last row (nil/blank → first page). Shared by the
  # controller (HTTP) and the Broadcaster (cable) so the paging logic lives in
  # exactly one place. The cursor's tuple shape — [read_bucket, created_at, id] —
  # is this model's concern; the pager JS treats the token as opaque.
  #
  # `limit` defaults to PAGE_SIZE — callers that don't pass it (the Broadcaster,
  # older clients) see unchanged behavior. NotificationsController#index clamps
  # the pito-tui viewport-driven `limit` param before it reaches here (owner
  # 2026-07-15).
  def self.panel_page(after: nil, limit: PAGE_SIZE)
    scope =
      if (cursor = Pito::ListCursor.decode(after))
        bucket, created_at, id = cursor
        panel_after(read_bucket: bucket.to_i, created_at: Time.iso8601(created_at.to_s), id: id.to_i)
      else
        panel_ordered
      end

    rows = scope.limit(limit + 1).to_a
    more = rows.size > limit
    rows = rows.first(limit)
    [ rows, (more ? cursor_for(rows.last) : nil) ]
  end

  # The opaque cursor token describing a row's position in panel_ordered.
  def self.cursor_for(row)
    bucket = row.read_at.nil? ? 1 : 0
    Pito::ListCursor.encode([ bucket, row.created_at.utc.iso8601(6), row.id ])
  end

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
