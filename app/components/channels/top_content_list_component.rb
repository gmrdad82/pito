# Phase 37 Top Content slice — Variant 1 (vertical ranked list).
#
# Renders a union-merged ranked list of top videos across the channels
# the user has selected on `/channels`. Each row carries:
#
#   <position>  <thumbnail-placeholder>  <title>  <views>  [ channel-badge ]
#
# Layout is a single vertical stack — one row per video. Most data-
# permissive of the three variants; comfortable on the eyes; visually
# echoes the rest of /channels' linear chrome.
#
# Mock data this slice — pulled from `Channels::MockData.top_content`
# upstream by the index view; the component itself stays presentational
# (no service calls inside the component) so the Wave B swap to real
# data is a constant change at the view layer.
#
# Channel-of-origin badge — bracketed muted text (`[ Studio Aurora ]`)
# in the right column so the eye reads the title + count first and the
# channel attribution last. Matches the `[ YouTube Studio ]` convention
# already used on the `Channels::IdCardComponent` footer.
class Channels::TopContentListComponent < ViewComponent::Base
  # @param videos [Array<Hash>] mock video hashes — see
  #   `Channels::MockData.top_content` for the schema. Already filtered
  #   to the channels the page is rendering and SORTED by views desc.
  # @param channel_name_by_id [Hash{Integer=>String}] id-to-display-name
  #   map so each row's channel badge renders without a per-row lookup.
  # @param limit [Integer] max rows to render. Defaults to 15 (10-15
  #   visible at a time per spec).
  def initialize(videos:, channel_name_by_id:, limit: 15)
    @videos = videos.first(limit)
    @channel_name_by_id = channel_name_by_id
  end

  attr_reader :videos, :channel_name_by_id

  def channel_name_for(video)
    channel_name_by_id[video[:channel_id]] || "channel ##{video[:channel_id]}"
  end

  def views_formatted(video)
    Formatting::CompactCount.call(video[:views])
  end

  # Fixed 48 px thumbnail placeholder — small enough to keep the row
  # compact, large enough to hint where the real `mqdefault.jpg` will
  # land in Wave B. 16:9 aspect ratio so the placeholder matches the
  # eventual YouTube thumbnail shape.
  def thumbnail_box_style
    "width: 80px; height: 45px; flex-shrink: 0; background: var(--color-channel-id-card-bg); border: 1px solid var(--color-border); border-radius: 2px;"
  end
end
