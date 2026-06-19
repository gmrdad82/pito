# frozen_string_literal: true

# DAILY release-countdown reminder.
#
# Selects every game whose `release_date` is PRESENT and falls within the next
# 30 days (today .. today + 30), computes the whole days remaining, and drops a
# witty reminder Notification per game. Date-less / TBA games (nil
# `release_date`) are skipped — the whole point of this job is replacing the old
# date-less summary with concrete, dated countdowns.
#
# == Same-day-per-game dedup
#
# The `Notification` schema is message-only — there is no `dedup_key` column to
# lean on. To guarantee at most one countdown per game per day we embed an
# invisible, stable HTML-comment MARKER in each message
# (`<!-- pito:release_countdown:game-<id> -->`) and, before creating a
# notification, check whether one carrying THIS game's marker already exists
# among today's notifications. Why a marker and not a title match:
#
#   * A bare title `LIKE` check collides across games (one title a substring of
#     another) AND with other notifications that list titles (the nightly sync
#     summary embeds changed/failed titles), producing false "already sent"
#     skips.
#   * The marker keys on the immutable game id, contains only
#     `[a-z0-9:-]` (no SQL-wildcard chars), and is HTML-invisible in the
#     rendered notification, so it is safe to `LIKE`-match and never shows to
#     the user.
#
# The trailing space in the marker (`game-1 -->`) keeps `game-1` from matching
# `game-12` under `LIKE`.
class ReleaseCountdownJob < ApplicationJob
  queue_as :default

  COUNTDOWN_WINDOW = 30.days

  def perform
    window_end = Date.current + COUNTDOWN_WINDOW

    Game.where(release_date: Date.current..window_end).find_each do |game|
      next if already_reminded_today?(game)

      days_remaining = (game.release_date - Date.current).to_i
      body = Pito::Notifications::Source::ReleaseCountdown.message(
        game: game, days_remaining: days_remaining
      )

      Notification.create!(message: "#{body}#{marker(game)}")
    end
  end

  private

  # Invisible, stable per-game marker appended to the message so a same-day
  # re-run can recognise its own prior reminder.
  def marker(game)
    " <!-- pito:release_countdown:game-#{game.id} -->"
  end

  def already_reminded_today?(game)
    Notification
      .where(created_at: Date.current.all_day)
      .where("message LIKE ?", "%pito:release_countdown:game-#{game.id} %")
      .exists?
  end
end
