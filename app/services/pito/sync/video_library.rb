# frozen_string_literal: true

module Pito
  module Sync
    # Shared, turn-less video-library sync for a single channel — the single home
    # for all YouTube video sync. Every caller (the cron `VideoSyncJob` fan-out and
    # the chat sync/import verbs) routes through it; their outer responsibilities
    # (turn/broadcast for chat, notification for cron) stay in the jobs.
    #
    # Entry points:
    #   - #import_new — discover + import uploads NEWER than our latest local
    #     video via `search.list?forMine` (owner-complete, so PRIVATE uploads
    #     included); on a channel's first run (no local videos) it discovers the
    #     full library. No uploads playlist — that public list hides private.
    #   - #reconcile  — update existing rows (attributes + Pito::Stats) + hard-
    #     delete uploads removed on YouTube (cascading thumbnail, stats, links).
    #   - #sync       — #import_new then #reconcile, merged into one Result; the
    #     canonical full per-channel sync. `import` and `sync` verbs both use it.
    #
    # Counters persist via `Pito::Stats`; thumbnail + Voyage-index jobs are
    # enqueued as needed. Per-page and per-video errors are rescued + logged so a
    # single bad API call or row never aborts the whole sync.
    class VideoLibrary
      # Outcome of a sync: `imported` (newly-created), `updated` (existing rows
      # whose attributes/stats changed), `deleted` (hard-deleted), and `titles`
      # (imported + deleted titles, for the summary).
      Result = Data.define(:imported, :updated, :deleted, :titles)

      # Max videos.list batch size per the YouTube API.
      BATCH_SIZE = 50

      # Video fields that feed `Video::EmbedText` — a change to any of these is
      # the only reason to re-embed (and recompute the channel centroid).
      EMBED_FIELDS = %w[title description tags category_id].freeze

      # Bookkeeping columns that `#upsert` touches on every save (it always
      # bumps `last_synced_at`). A save that only changed these is `:unchanged`
      # as far as reconciliation's "updated" count is concerned.
      SYNC_TIMESTAMP_FIELDS = %w[last_synced_at created_at updated_at].freeze

      def initialize(channel)
        @channel = channel
      end

      # Discover and import new uploads via `search.list?forMine` — the only
      # owner-complete listing, so PRIVATE uploads (and anything you flip in
      # YouTube Studio) are included, unlike the public uploads playlist. The
      # search is bounded with `published_after` = the newest locally-known
      # `published_at` + `order: "date"`, so normally only genuinely newer
      # uploads are fetched; on a channel's FIRST run (no local videos) there is
      # no lower bound and the full owner library is discovered.
      #
      # Only ids not already local are imported here — existing videos are
      # refreshed (and deletions handled) by {#reconcile}.
      #
      # @return [Result] whose `imported`/`titles` describe newly-created rows
      def import_new
        return empty_result if channel.youtube_connection.nil?

        ids = discover_video_ids(published_after: channel.videos.maximum(:published_at))
        return empty_result if ids.empty?

        existing = channel.videos.where(youtube_video_id: ids).pluck(:youtube_video_id)
        new_ids  = ids - existing
        return empty_result if new_ids.empty?

        imported = 0
        titles   = []

        new_ids.each_slice(BATCH_SIZE) do |batch|
          fetch_video_details(batch).each do |attrs|
            title = attrs[:title]
            next unless upsert(attrs) == :created

            imported += 1
            titles << title
          end
        end

        Result.new(imported:, updated: 0, deleted: 0, titles:)
      end

      # Full per-channel sync — the SINGLE entry point used by both the cron
      # fan-out (`VideoSyncJob`) and the chat sync/import verbs. Imports
      # new/private uploads ({#import_new}) THEN reconciles existing rows
      # ({#reconcile} — attribute updates + hard-delete of removed uploads),
      # returning one merged {Result}. Import runs first so freshly-imported
      # rows are already present when reconcile lists them.
      #
      # @return [Result] imported (new) + updated + deleted, with all titles
      def sync
        imported   = import_new
        reconciled = reconcile
        Result.new(
          imported: imported.imported,
          updated:  reconciled.updated,
          deleted:  reconciled.deleted,
          titles:   imported.titles + reconciled.titles
        )
      end

      # Targeted refresh of specific existing videos by YouTube id — `videos.list`
      # + upsert (attributes + Pito::Stats), with NO discovery and NO deletion.
      # Backs the `sync videos only <ids>` form. Returns a {Result} whose
      # `updated` counts rows whose attributes/stats actually changed.
      #
      # @param youtube_video_ids [Array<String>]
      # @return [Result]
      def refresh(youtube_video_ids)
        ids = Array(youtube_video_ids).compact
        return empty_result if ids.empty?

        updated = 0
        ids.each_slice(BATCH_SIZE) do |batch|
          fetch_video_details(batch).each { |attrs| updated += 1 if upsert(attrs) == :updated }
        end

        Result.new(imported: 0, updated:, deleted: 0, titles: [])
      end

      # Upsert a single normalized video attrs hash into the local table.
      #
      # @param attrs [Hash] normalized attributes from {#normalize_video}
      # @return [Symbol] `:created` when a new row was inserted, `:updated`
      #   when an existing row's attributes changed (beyond the sync
      #   bookkeeping columns), `:unchanged` otherwise (including failures)
      def upsert(attrs)
        return :unchanged if attrs[:youtube_video_id].blank?

        # View/like/comment counts live on the polymorphic `stats` table,
        # not video columns; pull them out of the AR attrs and persist via the
        # facade.
        views    = attrs.delete(:view_count)
        likes    = attrs.delete(:like_count)
        comments = attrs.delete(:comment_count)
        # Thumbnails are cached as OUR ActiveStorage copy (not a column) — pull
        # the source URL out of the AR attrs and ingest it off the import path.
        thumb_url = attrs.delete(:thumbnail_url)

        video = ::Video.find_or_initialize_by(youtube_video_id: attrs[:youtube_video_id])
        video.channel = channel
        video.assign_attributes(attrs)
        video.last_synced_at = Time.current
        video.save!

        ::Pito::Stats.set(video, :views, views)
        ::Pito::Stats.set(video, :likes, likes)
        ::Pito::Stats.set(video, :comments, comments)
        ::VideoThumbnailJob.perform_later(video.id, thumb_url) if thumb_url.present?

        # (Re)embed the video when it's new or an embedded field changed.
        # `Video::VoyageIndexer` is digest-gated, and `VideoVoyageIndexJob` only
        # refreshes the channel centroid when the video actually re-embeds, so
        # an unchanged re-import enqueues nothing wasteful here.
        if video.previously_new_record? || video.saved_changes.keys.intersect?(EMBED_FIELDS)
          ::VideoVoyageIndexJob.perform_later(video.id)
        end

        upsert_status(video)
      rescue StandardError => e
        Rails.logger.error(
          "[Pito::Sync::VideoLibrary] failed to upsert video " \
          "#{attrs[:youtube_video_id]} for channel=#{channel.id}: #{e.class}: #{e.message}"
        )
        :unchanged
      end

      # Reconcile our existing rows against YouTube's current truth. With the
      # owner's auth, `videos.list` RETURNS private videos but returns NOTHING
      # for a video that was deleted on YouTube. So for each of our known ids:
      # an id that comes back still exists (upsert it); an id ABSENT from the
      # response was deleted upstream and is hard-deleted locally (cascading
      # links, stats, thumbnail and embedding via `dependent: :destroy`).
      #
      # Linked games of every deleted video have their materialized footage/
      # stats recomputed via `GameStatsRefreshJob`.
      #
      # @return [Result] whose `updated`/`deleted`/`titles` describe the run
      def reconcile
        existing_ids = channel.videos.pluck(:youtube_video_id).compact
        return empty_result if existing_ids.empty?

        updated        = 0
        deleted_titles = []
        game_ids       = []

        existing_ids.each_slice(BATCH_SIZE) do |batch|
          returned_ids = reconcile_batch(batch) { |status| updated += 1 if status == :updated }
          next if returned_ids.nil?

          (batch - returned_ids).each do |video_id|
            destroy_absent_video(video_id, deleted_titles:, game_ids:)
          end
        end

        game_ids.uniq.each { |game_id| ::GameStatsRefreshJob.perform_later(game_id) }

        Result.new(imported: 0, updated:, deleted: deleted_titles.size, titles: deleted_titles)
      end

      private

      attr_reader :channel

      def client
        @client ||= ::Channel::Youtube::Client.new(channel.youtube_connection)
      end

      # Classify a just-saved video for the upsert callers' counters.
      def upsert_status(video)
        return :created if video.previously_new_record?

        meaningful = video.saved_changes.keys - SYNC_TIMESTAMP_FIELDS
        meaningful.any? ? :updated : :unchanged
      end

      # Fetch + upsert one batch of our existing ids and return the ids YouTube
      # returned (still-existing videos). Returns `nil` when the API call fails
      # so the caller skips deletion for this batch — a transient API error must
      # never be read as "every video in the batch was deleted".
      def reconcile_batch(batch)
        response = client.videos_list(
          ids: batch,
          parts: %i[snippet statistics contentDetails status]
        )

        Array(response[:items]).map do |item|
          attrs = normalize_video(item)
          yield upsert(attrs)
          attrs[:youtube_video_id]
        end
      rescue StandardError => e
        Rails.logger.error("[Pito::Sync::VideoLibrary] reconcile batch failed for channel=#{channel.id}: #{e.class}: #{e.message}")
        nil
      end

      # Hard-delete one video that YouTube no longer returns, capturing its
      # linked game ids first so their stats can be recomputed afterwards. A
      # per-video failure is logged and skipped so it can't abort the rest.
      def destroy_absent_video(youtube_video_id, deleted_titles:, game_ids:)
        video = channel.videos.find_by(youtube_video_id:)
        return unless video

        linked_game_ids = video.video_game_links.pluck(:game_id)
        title           = video.title
        video.destroy!
        deleted_titles << title
        game_ids.concat(linked_game_ids)
      rescue StandardError => e
        Rails.logger.error("[Pito::Sync::VideoLibrary] reconcile failed to destroy video #{youtube_video_id} for channel=#{channel.id}: #{e.class}: #{e.message}")
      end

      def empty_result
        Result.new(imported: 0, updated: 0, deleted: 0, titles: [])
      end

      # Page through `search.list?forMine=true&order=date`, collecting the
      # owner-complete set of video ids (private uploads included).
      #
      # YouTube REJECTS `forMine` + `publishedAfter` together (400 badRequest),
      # so we cannot bound the call server-side — doing so 400s on every run
      # once a channel has any local videos (non-nil cursor), which silently
      # discovered NOTHING. Instead we scan newest-first and stop client-side
      # the moment we cross `published_after` (the newest local upload). A nil
      # cursor (a channel's first run) walks the full owner library. One bad
      # page is logged and treated as the end of discovery rather than aborting.
      def discover_video_ids(published_after:)
        ids = []
        page_token = nil

        loop do
          response = client.search_list(
            for_mine: true,
            type: "video",
            order: "date",
            parts: %i[id snippet],
            max_results: 50,
            page_token: page_token
          )

          crossed = false
          Array(response[:items]).each do |item|
            video_id = item.dig(:id, :video_id)
            next if video_id.blank?

            if published_after
              published_at = parse_time(item.dig(:snippet, :published_at))
              # order=date is newest-first: the first upload at/older than the
              # cursor means every later item is older too — stop discovery.
              if published_at && published_at <= published_after
                crossed = true
                break
              end
            end

            ids << video_id
          end

          break if crossed

          page_token = response[:next_page_token]
          break if page_token.blank?
        end

        ids
      rescue StandardError => e
        Rails.logger.error("[Pito::Sync::VideoLibrary] discover_video_ids failed: #{e.class}: #{e.message}")
        []
      end

      def fetch_video_details(ids)
        return [] if ids.empty?

        response = client.videos_list(
          ids: ids,
          parts: %i[snippet statistics contentDetails status]
        )

        Array(response[:items]).map { |item| normalize_video(item) }
      rescue StandardError => e
        Rails.logger.error("[Pito::Sync::VideoLibrary] fetch_video_details failed: #{e.class}: #{e.message}")
        []
      end

      def normalize_video(item)
        snippet = item[:snippet] || {}
        stats   = item[:statistics] || {}
        details = item[:content_details] || {}
        status  = item[:status] || {}
        thumbs  = snippet[:thumbnails] || {}
        high    = thumbs[:high] || thumbs[:default] || {}

        {
          youtube_video_id: item[:id],
          title:            snippet[:title],
          description:      snippet[:description],
          published_at:     parse_time(snippet[:published_at]),
          privacy_status:   map_privacy(status[:privacy_status]),
          publish_at:       parse_time(status[:publish_at]),
          duration_seconds: parse_duration(details[:duration]),
          view_count:       stats[:view_count]&.to_i || 0,
          like_count:       stats[:like_count]&.to_i || 0,
          comment_count:    stats[:comment_count]&.to_i || 0,
          thumbnail_url:    high[:url],
          tags:             Array(snippet[:tags]),
          category_id:      snippet[:category_id]
        }
      end

      def map_privacy(status)
        case status.to_s.downcase
        when "public"   then :public
        when "unlisted" then :unlisted
        else :private
        end
      end

      def parse_time(value)
        return nil if value.blank?
        return value.to_time if value.respond_to?(:to_time)
        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def parse_duration(iso8601)
        return nil if iso8601.blank?

        match = iso8601.to_s.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
        return nil unless match

        hours = match[1].to_i
        mins  = match[2].to_i
        secs  = match[3].to_i
        (hours * 3600) + (mins * 60) + secs
      rescue StandardError
        nil
      end
    end
  end
end
