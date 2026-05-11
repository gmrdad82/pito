# Phase 7.5 §11d — Channel preview helper.
#
# Owns the static fixtures the `ChannelPreviewComponent` falls back
# to when the channel has no real Pito-tracked videos yet (a fresh
# post-OAuth channel, or one whose `videos.where.not(title: nil)`
# count is < 6). The titles are neutral, English-only test
# fixtures — never user-facing copy. The thumbnails are JPEGs the
# user drops into `public/preview/video_thumbnails/` (filenames
# `thumb-01.jpg` through `thumb-08.jpg`); the directory ships empty
# in the repo and the component falls back to a muted
# `[ no preview thumbnails yet ]` line when no files are present.
#
# Phase 7.5 §11e — Channel watermark preview.
#
# Extends the helper with `random_watermark_frame(seed:)` (now
# implemented — replaces the 11d placeholder stub) and
# `format_watermark_timing(timing, offset_ms)`. The watermark
# preview component composes the player chrome over a static JPEG
# the user drops into `public/preview/watermark_frames/` (filenames
# free-form, anything matching `*.jpg` / `*.jpeg`). The directory
# ships empty in the repo and the component falls back to a muted
# `[no preview frames yet]` line when no files are present.
module PreviewHelper
  RANDOM_VIDEO_TITLES = [
    "Morning routine that actually sticks",
    "I tried the cheapest mic on the market",
    "What we built this week",
    "Editing this took longer than filming",
    "The setup I wish I had two years ago",
    "Three small wins, one quiet loss",
    "Why I stopped chasing the algorithm",
    "Walking through the new home studio",
    "First impressions of the new lens",
    "A boring video about a boring task",
    "Reading the comments so you don't have to",
    "Behind the scenes of the last upload",
    "Trying every keyboard on my desk",
    "The folder structure I finally settled on",
    "Late-night thoughts on shipping",
    "One question that changed my workflow",
    "Notes from a week off",
    "Rebuilding the home page from scratch",
    "Things I learned recording this",
    "The plan for the next ten videos"
  ].freeze

  # Directory (under `public/`) that holds the static thumbnail
  # JPEGs the preview component falls back to. Lives in `public/`
  # so the rendered `<img>` tag can hit the file directly without
  # a controller round-trip.
  THUMBNAILS_DIR = Rails.root.join("public/preview/video_thumbnails").freeze
  THUMBNAIL_GLOB = "thumb-*.jpg"

  # Directory (under `public/`) that holds the static JPEG frames
  # the watermark preview component uses as the faux-player
  # background. User-supplied content; the repo ships an empty
  # directory with a `.keep` placeholder. Filenames are free-form
  # so the user can drop screenshots of varying names without
  # renaming first; the helper accepts both `.jpg` and `.jpeg`.
  WATERMARK_FRAMES_DIR = Rails.root.join("public/preview/watermark_frames").freeze
  WATERMARK_FRAME_GLOB = "*.{jpg,jpeg}"

  # Returns the public URL path for one of the static thumbnail
  # JPEGs, picked deterministically from `seed:` (modulo the number
  # of files actually present). Returns `nil` when the directory
  # is empty (no `thumb-*.jpg` files) so the caller can render the
  # `[ no preview thumbnails yet ]` fallback copy.
  def self.random_video_thumbnail(seed:)
    files = available_thumbnail_files
    return nil if files.empty?

    chosen = files[seed.to_i.abs % files.size]
    "/preview/video_thumbnails/#{chosen}"
  end

  # Returns the public URL path for one of the static watermark
  # frames, picked deterministically from `seed:` (modulo the
  # number of files actually present). Returns `nil` when the
  # directory is empty so the caller can render the
  # `[no preview frames yet]` fallback copy.
  #
  # Determinism mirrors `random_video_thumbnail`: the channel-id
  # seed means the same channel always shows the same background
  # across reloads, so the user isn't surprised by a different
  # frame after every save.
  def self.random_watermark_frame(seed:)
    files = available_watermark_frames
    return nil if files.empty?

    chosen = files[seed.to_i.abs % files.size]
    "/preview/watermark_frames/#{chosen}"
  end

  # Renders a short human-readable caption describing how the
  # watermark will appear in the player based on the channel's
  # `watermark_timing` + `watermark_offset_ms`. The DB stores
  # offsets in milliseconds; the caption converts to whole
  # seconds at the render boundary (per locked Q3 — seconds, not
  # milliseconds, for readability).
  #
  #   timing:    one of "always" / "entire_video" /
  #              "offset_from_start" / "offset_from_end" / nil.
  #   offset_ms: integer-coercible value, ignored unless timing
  #              is one of the offset variants.
  #
  # Returns:
  #   "Visible: always"            for "always" or "entire_video"
  #   "Visible: starts at <N>s"    for "offset_from_start"
  #   "Visible: last <N>s"         for "offset_from_end"
  #   "No watermark set"           when timing is nil/blank
  #                                (caller decided no watermark is
  #                                present).
  def self.format_watermark_timing(timing, offset_ms)
    case timing.to_s
    when "always", "entire_video"
      "Visible: always"
    when "offset_from_start"
      "Visible: starts at #{offset_seconds(offset_ms)}s"
    when "offset_from_end"
      "Visible: last #{offset_seconds(offset_ms)}s"
    else
      "No watermark set"
    end
  end

  # Picks `count` titles from `RANDOM_VIDEO_TITLES`, seeded so
  # repeated calls within a single render return the same titles
  # in the same order. Falls back to wrap-around when the pool is
  # smaller than `count` (which it never is in practice, but the
  # guard keeps the helper crash-free).
  def self.sample_titles(count:, seed:)
    return [] if count <= 0

    pool = RANDOM_VIDEO_TITLES
    base = seed.to_i.abs
    Array.new(count) { |i| pool[(base + i) % pool.size] }
  end

  # Lists the basenames of every `thumb-*.jpg` file present in
  # `public/preview/video_thumbnails/`. Sorted alphabetically so
  # the seed-based selection stays stable across reloads.
  def self.available_thumbnail_files
    return [] unless Dir.exist?(THUMBNAILS_DIR)

    Dir.children(THUMBNAILS_DIR)
       .select { |f| File.fnmatch(THUMBNAIL_GLOB, f) }
       .sort
  end

  # Lists the basenames of every JPEG file present in
  # `public/preview/watermark_frames/`. Sorted alphabetically so
  # the seed-based selection stays stable across reloads. Accepts
  # both `.jpg` and `.jpeg` (matches the glob in `WATERMARK_FRAME_GLOB`).
  def self.available_watermark_frames
    return [] unless Dir.exist?(WATERMARK_FRAMES_DIR)

    Dir.children(WATERMARK_FRAMES_DIR)
       .select { |f| File.fnmatch(WATERMARK_FRAME_GLOB, f, File::FNM_EXTGLOB) }
       .sort
  end

  # Internal — converts a millisecond offset to a whole-second
  # display string. Negative or non-numeric values collapse to 0.
  def self.offset_seconds(offset_ms)
    raw = offset_ms.to_i
    return 0 if raw.negative?

    (raw / 1000.0).round
  end
  private_class_method :offset_seconds
end
