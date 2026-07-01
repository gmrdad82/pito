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

    dated = GamePlatformRelease
            .where.not(release_day: nil)
            .where(release_date: Date.current..window_end)
            .includes(:game)

    dated.group_by { |rel| [ rel.game_id, rel.release_date ] }.each do |(_game_id, date), rows|
      game = rows.first.game
      next if game.nil? || already_reminded?(game, date)

      body = Pito::Notifications::Source::ReleaseCountdown.message(
        game:           game,
        days_remaining: (date - Date.current).to_i,
        platforms:      platform_label(rows.map(&:platform_token))
      )

      Notification.create!(message: "#{body}#{marker(game, date)}")
    end
  end

  private

  # Human platform label(s) in canonical order, joined "PlayStation + Steam".
  def platform_label(tokens)
    tokens.uniq
          .sort_by { |t| Pito::Game::PlatformTokens::ORDER.index(t) || Pito::Game::PlatformTokens::ORDER.size }
          .map { |t| I18n.t("pito.game.platform_label.#{t}") }
          .join(" + ")
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
