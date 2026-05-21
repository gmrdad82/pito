# Phase 37 Top Content slice — Variant 2 (4-column tile grid).
#
# Renders a union-merged ranked list of top videos as a 4-column grid of
# tiles. Each tile: thumbnail placeholder + 2-line title + view count +
# channel badge. Compact, browse-friendly.
#
# Tile dimensions follow the same 16:9 thumbnail aspect ratio as
# Variant 1 — but the thumbnail spans the full tile width, with a fixed
# height computed from the grid column width at runtime by CSS
# (`aspect-ratio: 16/9` keeps it responsive).
class Channel::TopContentGridComponent < ViewComponent::Base
  # @param videos [Array<Hash>] sorted-desc mock video hashes.
  # @param channel_name_by_id [Hash{Integer=>String}] id-to-name map.
  # @param limit [Integer] max tiles to render. Default 12 (4 cols x 3 rows).
  def initialize(videos:, channel_name_by_id:, limit: 12)
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
