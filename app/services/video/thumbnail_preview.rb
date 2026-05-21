class Video
  # `Video::ThumbnailPreview` — "how does this thumbnail look in the
  # YouTube grid?" preview generation.
  #
  # ## Status
  #
  # Skeleton. Implementation deferred until `/videos` Edit panel ships
  # with the thumbnail workflow (see `Screen::Videos::ThumbnailPreviewPanelComponent`).
  #
  # ## Design options to revisit
  #
  # 1. Embed youtumbtv.com iframe inside the panel (current owner workflow)
  # 2. Native preview component that mimics the YouTube grid using
  #    locally-rendered thumbnails (full control, no external dep)
  #
  # Pick happens at `/videos` build time.
  class ThumbnailPreview
    # @param video [Video]
    # @return [Hash] preview metadata (TBD shape)
    def self.generate(video:)
      raise NotImplementedError,
            "Video::ThumbnailPreview pending /videos Edit panel build"
    end
  end
end
