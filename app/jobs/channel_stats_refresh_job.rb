# frozen_string_literal: true

# Recompute a Channel's materialized `likes` stat (sum of its videos' likes)
# off the request path — the channels sibling of GameStatsRefreshJob.
#
# Enqueue after every pass that rewrites video like counts (video sync,
# intraday stats snapshot). A missing channel is a no-op so a stale enqueue
# after a delete never raises.
class ChannelStatsRefreshJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    channel = Channel.find_by(id: channel_id)
    return unless channel

    Channel::StatsRefresh.call(channel)
  end
end
