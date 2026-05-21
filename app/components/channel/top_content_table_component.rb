# Phase 37 Top Content slice — Variant 3 (compact 3-column table).
#
# Tight data-dense table: title | views | channel. No thumbnails, no
# ranks. Each row is a single line — the highest information density
# of the three variants, closest to what a `pito` TUI surface would
# show. Channel column renders as a bracketed muted link to keep visual
# parity with the rest of /channels.
class Channel::TopContentTableComponent < ViewComponent::Base
  # @param videos [Array<Hash>] sorted-desc mock video hashes.
  # @param channel_name_by_id [Hash{Integer=>String}] id-to-name map.
  # @param limit [Integer] max rows to render. Default 20 (tight rows
  #   read comfortably at this length).
  def initialize(videos:, channel_name_by_id:, limit: 20)
    @videos = videos.first(limit)
    @channel_name_by_id = channel_name_by_id
  end

  attr_reader :videos, :channel_name_by_id

  def channel_name_for(video)
    channel_name_by_id[video[:channel_id]] || "channel ##{video[:channel_id]}"
  end

  def views_formatted(video)
    Pito::Formatter::CompactCount.call(video[:views])
  end
end
