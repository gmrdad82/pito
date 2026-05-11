# Phase 7.5 §11e — Channel watermark preview component.
#
# Renders a faux YouTube player (background frame + rough control
# strip + watermark overlay) at one of four size variants so the
# user can see roughly how their watermark will appear inside an
# embedded video. Layout-agnostic: the parent picks the `size:`
# variant — `:edit` for the inline preview next to the watermark
# form fields on `/channels/:slug/edit`, and `:desktop` / `:mobile`
# / `:tv` for the `ChannelPreviewComponent` (11d) modal.
#
# Watermark overlay is locked to the BOTTOM-RIGHT corner per the
# Step-11e locked decision (YouTube's UI per image #41); no
# position selector is exposed.
#
# Empty states:
#
#   * `public/preview/watermark_frames/` empty → faux player area
#     is replaced with a muted `[no preview frames yet]` line
#     (bracketed-link convention A: no inner padding spaces).
#   * channel has no `watermark_url` → player chrome still renders
#     (so the user sees the frame context) but the overlay is
#     omitted; the caption reads `"No watermark set"`.
class WatermarkPreviewComponent < ViewComponent::Base
  SIZES = %i[edit desktop mobile tv].freeze
  DEFAULT_SIZE = :edit

  attr_reader :channel, :size, :timing, :offset_ms

  # channel:    the Channel record. Reads `watermark_url`,
  #             `watermark_timing`, `watermark_offset_ms` from it
  #             unless the caller overrides via `timing:` / `offset_ms:`.
  # size:       one of `:edit`, `:desktop`, `:mobile`, `:tv`.
  # timing:     optional override for `channel.watermark_timing`
  #             (used by the form preview so the caption updates
  #             from form-field values without a save).
  # offset_ms:  optional override for `channel.watermark_offset_ms`.
  # frame_path: optional override for the background frame URL
  #             (primarily for tests; defaults to a random pick
  #             via `PreviewHelper.random_watermark_frame`).
  def initialize(channel:, size: DEFAULT_SIZE, timing: :unset, offset_ms: :unset, frame_path: :unset)
    @channel = channel
    @size = SIZES.include?(size) ? size : DEFAULT_SIZE
    @timing = timing == :unset ? channel&.watermark_timing : timing
    @offset_ms = offset_ms == :unset ? channel&.watermark_offset_ms : offset_ms
    @frame_path_override = frame_path
  end

  # Chosen background frame URL. Deterministic per channel id (so
  # reloads of the same channel show the same frame). Returns nil
  # when no frames are available; the view renders the muted
  # empty-state line in place of the player area.
  def frame_path
    return @frame_path_override unless @frame_path_override == :unset

    seed = channel&.id.to_i
    PreviewHelper.random_watermark_frame(seed: seed)
  end

  # True when the channel has a stored watermark URL. When false,
  # the overlay is omitted and the caption renders the
  # "No watermark set" line.
  def watermark?
    channel&.watermark_url.to_s.strip.present?
  end

  # Caption beneath the player. Delegates to
  # `PreviewHelper.format_watermark_timing` so the same logic is
  # available from non-component callers (e.g., the form helper).
  # When no watermark is set, the caption is always
  # "No watermark set" regardless of the timing value.
  def caption
    return "No watermark set" unless watermark?

    PreviewHelper.format_watermark_timing(timing, offset_ms)
  end

  # Empty-frames branch — true when the user has not dropped any
  # JPEGs into `public/preview/watermark_frames/`. The component
  # still renders the caption (so the user sees the timing
  # description even without a background frame).
  def empty_frames?
    frame_path.nil?
  end
end
