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
# `random_watermark_frame` is a stub for the 11e watermark preview
# sub-spec; 11d does NOT call it. It lives here so 11e can land
# without re-opening this file.
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

  # Stub for 11e (watermark preview). Defined here so the file
  # doesn't need to re-open when 11e lands. 11d MUST NOT call this.
  def self.random_watermark_frame(seed:) # rubocop:disable Lint/UnusedMethodArgument
    nil
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
end
