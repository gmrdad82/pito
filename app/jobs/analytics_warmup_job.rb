# frozen_string_literal: true

# Scheduled cache warming for the interactive analytics surfaces.
#
# Runs Pito::Analytics::Warmup for every connected (non-reauth) channel so
# `show` / `analyze` / `breakdowns` land on warm primitives + cells instead
# of paying YouTube Analytics round-trips inside the owner's turn. Scheduled
# at 01:35 and 13:35 UTC (config/recurring.yml) — after each sync pass.
# Live windows expire 4h after fetch (Window policy), so afternoon/evening
# first-turns can still go cold; add recurring slots if that ever grates.
#
# Turn-less by design: no broadcast, no Notification — the only observable
# effect is warm caches (and the audit rows the fills write). A channel
# failure is rescued + logged so siblings still warm, mirroring the other
# recurring fleet jobs.
class AnalyticsWarmupJob < ApplicationJob
  queue_as :default

  def perform
    connected_channels.find_each do |channel|
      Pito::Analytics::Warmup.call(channel:)
    rescue StandardError => e
      # Isolation stays (siblings warm on); the failure ALSO becomes an
      # AppSignal incident — report_error no-ops when AppSignal is inactive.
      Appsignal.report_error(e)
      Rails.logger.error(
        "AnalyticsWarmupJob: failed for channel=#{channel.id}: " \
        "#{e.class}: #{e.message}"
      )
    end
  end

  private

  def connected_channels
    ::Channel
      .joins(:youtube_connection)
      .where(youtube_connections: { needs_reauth: false })
  end
end
