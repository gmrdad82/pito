# Phase 22 §6.2 — Channels::VideoImporter.
#
# Service seam between `Channel::ImportVideosJob` and the upstream
# YouTube `playlistItems.list` API. Encapsulates pagination + diffing +
# row creation; yields `PageProgress` so the caller can update the
# `ImportJob` counters and broadcast progress without the service
# learning about Action Cable.
#
# This phase ships with a pluggable `playlist_client:` constructor
# argument so tests can stub the upstream call without touching live
# wire. The real `playlistItems.list` adapter lands when OAuth wires
# in (Phase 7 / Phase 8 lane). Until then a deliberately-named stub
# (`StubPlaylistClient.new(pages: [...])`) is the only legitimate
# caller in production code paths.
#
# Errors:
#   - Transient — `Channels::VideoImporter::TransientError` (re-raise
#     so Sidekiq retries; the job class wraps the raise).
#   - Permanent — `Channels::VideoImporter::FatalError` with
#     `suppress_retry: true`. The job class catches this, marks the
#     ImportJob `failed`, and stops the retry loop.
module Channels
  class VideoImporter
    # Per-page progress payload yielded to the block.
    PageProgress = Struct.new(:total, :imported, keyword_init: true)

    class FatalError < StandardError
      attr_reader :code, :suppress_retry

      def initialize(code:, message:, suppress_retry: true)
        super(message)
        @code = code
        @suppress_retry = suppress_retry
      end

      alias_method :suppress_retry?, :suppress_retry
    end

    class TransientError < StandardError
      attr_reader :code

      def initialize(code:, message:)
        super(message)
        @code = code
      end
    end

    # The upstream client returns hashes shaped like
    # `{ items: [{ youtube_video_id:, title:, duration_seconds:, category_id: }, ...],
    #    next_page_token: nil_or_string }`. The shape is decoupled from
    # the YouTube SDK's literal response so swapping the upstream
    # implementation in Phase 7/8 is a single-file change.
    def initialize(playlist_client: nil)
      @playlist_client = playlist_client || default_playlist_client
    end

    def call(channel:, import_job:)
      raise FatalError.new(code: :channel_missing_connection,
                           message: "channel has no YouTube connection") if channel.youtube_connection_id.nil?

      uploads_playlist_id = resolve_uploads_playlist(channel)
      raise FatalError.new(code: :no_uploads_playlist,
                           message: "channel has no uploads playlist") if uploads_playlist_id.blank?

      paginate(uploads_playlist_id) do |items|
        process_page(channel: channel, import_job: import_job, items: items)
        yield PageProgress.new(
          total: import_job.total_videos,
          imported: import_job.imported_videos
        ) if block_given?
      end
    end

    private

    # Override seam — real wiring lands when OAuth ships. The stub
    # accepts a hash of `playlist_id => pages` for the offline test
    # surface.
    def default_playlist_client
      StubPlaylistClient.new
    end

    def resolve_uploads_playlist(channel)
      @playlist_client.uploads_playlist_id(channel: channel)
    end

    def paginate(playlist_id)
      page_token = nil
      loop do
        page = @playlist_client.list_page(playlist_id: playlist_id, page_token: page_token)
        items = page.fetch(:items, [])
        yield items if items.any? || page_token.nil?
        page_token = page[:next_page_token]
        break if page_token.blank?
      end
    end

    def process_page(channel:, import_job:, items:)
      return if items.empty?

      ids_in_page = items.map { |i| i[:youtube_video_id] }.compact
      existing_ids = channel.videos.where(youtube_video_id: ids_in_page).pluck(:youtube_video_id).to_set
      rejected_ids = channel.rejected_video_imports
                            .where(youtube_video_id: ids_in_page)
                            .pluck(:youtube_video_id).to_set

      created = 0
      items.each do |item|
        yid = item[:youtube_video_id]
        next if yid.blank?
        next if existing_ids.include?(yid)
        next if rejected_ids.include?(yid)

        # Build a Video row. Title is clipped to 100 chars (matches the
        # column limit on `videos.title`). Privacy_status stays at the
        # default `:private` — the YouTube-side privacy / published_at
        # values arrive on the next sync round-trip (post-OAuth). New
        # rows from the import pipeline are deliberately conservative.
        record = channel.videos.create(
          youtube_video_id: yid,
          title: item[:title].to_s.first(100),
          category_id: item[:category_id],
          duration_seconds: item[:duration_seconds]
        )
        if record.persisted?
          created += 1
        else
          Rails.logger.warn(
            "[Channels::VideoImporter] failed to create video for #{yid}: #{record.errors.full_messages.join('; ')}"
          )
        end
      end

      # Atomic counter bump — read the persisted columns rather than the
      # in-memory copy so concurrent updates can't clobber each other.
      # Sanitized via `Arel.sql` + integer coercion — `items.size` and
      # `created` are both produced internally as integers and never
      # routed through user input, but the explicit cast pins the
      # contract so Brakeman / future refactors stay safe.
      delta_total    = items.size.to_i
      delta_imported = created.to_i
      ImportJob.where(id: import_job.id).update_all(
        ActiveRecord::Base.sanitize_sql_array([
          "total_videos = total_videos + ?, imported_videos = imported_videos + ?",
          delta_total, delta_imported
        ])
      )
      import_job.reload
    end

    # Default in-process stub. Useful only for the manual playbook /
    # rake task that wants to drive the modal without OAuth wiring; real
    # tests always inject their own client.
    class StubPlaylistClient
      def uploads_playlist_id(channel:)
        # Conventional YouTube uploads-playlist id: replace the `UC`
        # prefix of the channel id with `UU`. Pre-OAuth this is a
        # deterministic-enough placeholder for the test/dev branches.
        channel.url_slug&.sub(/\AUC/, "UU")
      end

      def list_page(playlist_id:, page_token: nil)
        { items: [], next_page_token: nil }
      end
    end
  end
end
