# frozen_string_literal: true

# DAILY release-countdown reminder (Item 24 — per-platform).
#
# Selects every PER-PLATFORM release (GamePlatformRelease) that is DAY-PRECISION
# (release_day present) and falls within the next 30 days, groups them by
# (game, date), and drops one witty reminder Notification per group naming the
# platform(s) hitting that date ("… on PlayStation + Steam in 3 days").
#
# Only day-precision rows count down — a quarter/year lower-bound is not a real
# release day (this is the Item 23 fix: never count "0 days" to a quarter).
# Games with no dated per-platform release are silently skipped.
#
# == One digest webhook, not N
#
# Each per-group Notification is created with `skip_webhook: true` — the
# in-app record and mini-status badge still land per group, but the
# individual `NotificationWebhookDeliverJob` is suppressed. Instead every
# newly-created group's `[countdown, title]` is collected into `rows` and,
# once the loop finishes, sent as ONE `Pito::Notifications::WebhookDigest`
# call — a single colored Slack/Discord message listing every upcoming
# release instead of a flood of individual webhooks.
#
# == Same-day per (game, date) dedup
#
# The `Notification` schema is message-only — no dedup_key column. We embed an
# invisible, stable HTML-comment MARKER
# (`<!-- pito:release_countdown:game-<id>:<iso-date> -->`) in each message and,
# before creating one, check whether a notification carrying THIS game+date
# marker already exists among today's notifications. The marker keys on the
# immutable game id + the release date (both `[a-z0-9:-]`, no SQL wildcards) and
# is HTML-invisible. The trailing space (`…:2026-07-31 -->`) keeps one marker
# from prefix-matching another under `LIKE`.
class ReleaseCountdownJob < ApplicationJob
  queue_as :default

  COUNTDOWN_WINDOW = 30.days

  def perform
    window_end = Date.current + COUNTDOWN_WINDOW
    digest_rows = []

    dated = GamePlatformRelease
            .where.not(release_day: nil)
            .where(release_date: Date.current..window_end)
            .includes(:game)

    dated.group_by { |rel| [ rel.game_id, rel.release_date ] }
         .sort_by { |(_game_id, date), _platform_rows| date }
         .each do |(_game_id, date), platform_rows|
      game = platform_rows.first.game
      next if game.nil? || already_reminded?(game, date)

      days_remaining = (date - Date.current).to_i
      body = Pito::Notifications::Source::ReleaseCountdown.message(
        game:           game,
        days_remaining: days_remaining,
        platforms:      platform_label(platform_rows.map(&:platform_token))
      )

      Notification.create!(message: "#{body}#{marker(game, date)}", skip_webhook: true)
      digest_rows << [ countdown_label(days_remaining), game.title ]
    end

    Pito::Notifications::WebhookDigest.call(
      title:  "🎮 Upcoming releases",
      accent: Pito::Notifications::WebhookDigest::RELEASES,
      rows:   digest_rows
    )
  end

  private

  # Human platform label(s) in canonical order, joined "PlayStation + Steam".
  def platform_label(tokens)
    tokens.uniq
          .sort_by { |t| Pito::Games::PlatformTokens::ORDER.index(t) || Pito::Games::PlatformTokens::ORDER.size }
          .map { |t| I18n.t("pito.game.platform_label.#{t}") }
          .join(" + ")
  end

  # Digest col1 wording — "in 1 day" (singular), otherwise "in N days"
  # ("in 0 days" for a today release keeps the plural, which is correct).
  def countdown_label(days_remaining)
    days_remaining == 1 ? "in 1 day" : "in #{days_remaining} days"
  end

  # Invisible, stable per-(game, date) marker so a same-day re-run recognises its
  # own prior reminder.
  def marker(game, date)
    " <!-- pito:release_countdown:game-#{game.id}:#{date.iso8601} -->"
  end

  def already_reminded?(game, date)
    Notification
      .where(created_at: Date.current.all_day)
      .where("message LIKE ?", "%pito:release_countdown:game-#{game.id}:#{date.iso8601} %")
      .exists?
  end
end
