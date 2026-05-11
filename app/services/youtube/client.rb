# Phase 7 — Step B (7b-youtube-client-and-audit.md). The single
# rate-limit-aware YouTube client.
#
# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006). The
# constructor accepts a `YoutubeConnection`; internal naming follows.
#
# Every YouTube Data v3 / YouTube Analytics v2 call from pito flows
# through this object. Callers receive pito-shape Ruby Hashes
# (snake_case keys) — never `Google::Apis::YoutubeV3::Channel` structs.
#
# Lifecycle of a single call:
#   1. Resolve endpoint key.
#   2. `ensure_token_fresh!` — refresh if expires_at within 60s.
#   3. Pre-call quota check; raise QuotaExhaustedError if budget
#      would be exceeded.
#   4. Execute via the underlying gem; wrap retry/backoff per the
#      retry policy.
#   5. Audit a single row (one row per logical call) reflecting
#      the final outcome.
#   6. Convert the response shape and return.
require "google/apis/youtube_v3"
require "google/apis/youtube_analytics_v2"
require "google/apis/errors"

module Youtube
  class Client
    include Auditor

    KIND = "oauth"
    MAX_5XX_ATTEMPTS = 3
    RATE_LIMITED_DEFAULT_RETRY_AFTER = 5

    def initialize(youtube_connection)
      @connection = youtube_connection
    end

    # GET /youtube/v3/channels
    def channels_list(mine: nil, ids: nil, parts: %i[snippet statistics],
                      max_results: 50, page_token: nil)
      perform("channels.list", "GET") do
        svc = data_service
        opts = {
          max_results: max_results,
          page_token: page_token
        }
        opts[:mine] = (mine ? true : false) unless mine.nil?
        opts[:id] = Array(ids).join(",") if ids.present?

        response = svc.list_channels(parts.map(&:to_s).join(","), **opts)
        normalize_list(response)
      end
    end

    # Phase 7.5 §11a — Channel sync foundation. Single-call channel
    # fetch with the full part set the management surface needs to
    # cache (snippet + statistics + brandingSettings + contentDetails +
    # status). Returns a normalized snake_case Hash matching the spec's
    # `Channel` cached-column shape. Routes through the same `perform`
    # chokepoint as every other call so quota / refresh / audit
    # semantics stay uniform; the audit endpoint key remains
    # `channels.list` (cost 1).
    #
    # The `channel` argument is currently unused (the call is keyed by
    # the connection's `mine: true`), but the signature accepts it so
    # 11i's daily diff-check can call `fetch_channel(channel)` once per
    # connected channel without surface churn.
    FETCH_CHANNEL_PARTS = %i[snippet statistics brandingSettings contentDetails status].freeze

    def fetch_channel(_channel = nil)
      result = perform("channels.list", "GET") do
        svc = data_service
        response = svc.list_channels(
          FETCH_CHANNEL_PARTS.map(&:to_s).join(","),
          mine: true,
          max_results: 1
        )
        normalize_list(response)
      end

      item = result[:items].first
      normalize_channel_item(item)
    end

    # Phase 7.5 §11c — Channel edit form. Destructive PUT against
    # `channels.update` using the read-modify-write pattern: fetch the
    # current `brandingSettings` first, merge the caller's dirty subset
    # into the response body, then PUT the merged body back. Without
    # the read, YouTube treats every absent sibling field on PUT as a
    # blank-out request — which is how channels accidentally lose their
    # country, default language, or keywords.
    #
    # `field_set` is a Pito-shape Hash with one or more of:
    #   :title, :description, :country, :default_language, :keywords
    #
    # The `:handle` field is excluded from this entrypoint — YouTube
    # exposes a dedicated handle-management endpoint (verified by the
    # Phase 7.5 §11c research dispatch); see `#update_handle` for that
    # path. The controller branches between the two before dispatching.
    #
    # Returns the parsed response as a snake_case Ruby Hash matching
    # the `Channel` cached-column shape (`title`, `description`,
    # `country`, `default_language`, `keywords`). Never leaks the
    # `Google::Apis::YoutubeV3::Channel` struct to callers.
    UPDATE_CHANNEL_BRANDING_KEYS = %i[title description country default_language keywords].freeze

    def update_channel(channel, field_set)
      raise ArgumentError, "channel required" if channel.nil?
      raise ArgumentError, "field_set must be a Hash" unless field_set.is_a?(Hash)

      branding_keys = field_set.slice(*UPDATE_CHANNEL_BRANDING_KEYS)
      raise ArgumentError, "field_set has no supported keys" if branding_keys.empty?

      youtube_channel_id = extract_youtube_channel_id(channel)

      # Step 1 — read-modify-write phase 1: pull the current
      # brandingSettings so we can merge instead of blank-out.
      current_branding = read_current_branding(youtube_channel_id)

      # Step 2 — merge the Pito-shape dirty subset into the YouTube
      # snake_case branding hash. The Google gem accepts snake_case
      # attribute names on `ChannelBrandingSettings#channel`; the
      # representation layer flips them back to camelCase on the wire.
      merged_channel_section = current_branding.merge(
        branding_keys.compact.transform_keys(&:to_sym)
      )

      # Step 3 — destructive PUT. Pass `id` so YouTube knows which
      # channel we're updating (when `mine: true`-scoped, this is the
      # connected channel; explicit `id` is safer).
      perform("channels.update", "PUT") do
        svc = data_service
        branding_settings = Google::Apis::YoutubeV3::ChannelBrandingSettings.new(
          channel: Google::Apis::YoutubeV3::ChannelSettings.new(**merged_channel_section)
        )
        channel_object = Google::Apis::YoutubeV3::Channel.new(
          id: youtube_channel_id,
          branding_settings: branding_settings
        )
        response = svc.update_channel("brandingSettings", channel_object)
        normalize_channel_item(symbolize_struct(response))
      end
    end

    # Phase 7.5 §11i — handle push surface.
    #
    # YouTube exposes a dedicated handle-management endpoint that is
    # NOT part of `channels.update#brandingSettings`. The full API
    # surface lands with 11c follow-up research; until that ships the
    # stub raises `NotImplementedError` so an `accept pito` decision on
    # `handle` in the diff resolution flow surfaces a clear "this push
    # path isn't wired yet" error rather than a silent no-op.
    #
    # The method is left on the class (rather than removed) because
    # `Channels::DiffApply` dispatches `accept pito` on `handle`
    # through it; the dispatch chain is tested via stubbed clients
    # until the real endpoint ships.
    def update_handle(channel, value)
      raise ArgumentError, "channel required" if channel.nil?
      raise ArgumentError, "value required"   if value.nil?

      raise NotImplementedError,
            "Youtube::Client#update_handle is not yet wired — see Phase 7.5 §11c follow-up research. " \
            "Use the YouTube Studio UI to change the handle for now."
    end

    # Phase 7.5 §11c — uploads a new watermark image and sets the
    # accompanying timing. `io` is any IO-like object the user-supplied
    # file is exposed as (e.g., `params[:channel][:watermark]`, an
    # `ActionDispatch::Http::UploadedFile`). `timing` is one of the
    # values in `Channel::WATERMARK_TIMINGS`; `offset_ms` is required
    # iff `timing` is `offset_from_start` / `offset_from_end` and is
    # ignored otherwise.
    #
    # Returns the cached `watermark_url` (the `image_url` from the
    # parsed YouTube response). The caller uses that to populate
    # `channel.watermark_url` in the cache write that follows.
    WATERMARK_TIMING_API_MAPPING = {
      "always"             => "always",
      "entire_video"       => "entireVideo",
      "offset_from_start"  => "offsetFromStart",
      "offset_from_end"    => "offsetFromEnd"
    }.freeze

    def set_watermark(channel, io, timing, offset_ms = nil)
      raise ArgumentError, "channel required" if channel.nil?
      raise ArgumentError, "io required" if io.nil?
      raise ArgumentError, "unknown timing #{timing.inspect}" unless WATERMARK_TIMING_API_MAPPING.key?(timing.to_s)

      youtube_channel_id = extract_youtube_channel_id(channel)
      api_timing_type = WATERMARK_TIMING_API_MAPPING[timing.to_s]

      timing_object = Google::Apis::YoutubeV3::InvideoTiming.new(type: api_timing_type)
      if %w[offset_from_start offset_from_end].include?(timing.to_s)
        raise ArgumentError, "offset_ms required for #{timing}" if offset_ms.nil?
        timing_object.offset_ms = offset_ms.to_i
      end

      branding_object = Google::Apis::YoutubeV3::InvideoBranding.new(timing: timing_object)

      perform("watermarks.set", "POST") do
        svc = data_service
        content_type = io.respond_to?(:content_type) ? io.content_type : "image/png"
        svc.set_watermark(
          youtube_channel_id,
          branding_object,
          upload_source: io,
          content_type: content_type
        )
        # `watermarks.set` returns no body on success. The cached
        # watermark URL is opaque to us until the next channel sync
        # surfaces it, so the caller persists `timing` / `offset_ms`
        # locally and leaves `watermark_url` for the diff job (11i) to
        # backfill.
        { ok: true }
      end
    end

    def unset_watermark(channel)
      raise ArgumentError, "channel required" if channel.nil?

      youtube_channel_id = extract_youtube_channel_id(channel)

      perform("watermarks.unset", "POST") do
        svc = data_service
        svc.unset_watermark(youtube_channel_id)
        { ok: true }
      end
    end

    # Phase 7.5 §11f — two-step channel banner upload.
    #
    # Step 1: `channelBanners.insert` uploads the image bytes and
    #         returns a `ChannelBannerResource` whose `url` is the
    #         opaque-but-stable `bannerExternalUrl` token. The token
    #         is NOT a CDN URL — it is the upload handle YouTube
    #         expects to receive on the next call.
    # Step 2: `channels.update` (part=brandingSettings) writes
    #         `brandingSettings.image.bannerExternalUrl = <token>`,
    #         which is what actually publishes the banner. YouTube
    #         then echoes the cacheable CDN URL back in the response
    #         under `brandingSettings.image.bannerExternalUrl`.
    #
    # Both calls audit through `perform` so quota / refresh / retry
    # semantics stay uniform; the caller sees one combined operation
    # and two audit rows (one per endpoint).
    #
    # `io` is any IO-like object (e.g. `ActionDispatch::Http::
    # UploadedFile`) that responds to `read`, plus optionally
    # `content_type` and `original_filename`.
    #
    # Returns the cached `banner_external_url` string from the
    # `channels.update` response so the controller can persist it
    # into `channels.banner_url`. On any failure (auth, quota,
    # transient, dimensions rejected by YouTube despite the
    # client-side check), raises the structured Youtube::* error
    # the `perform` chokepoint produces so the controller can
    # surface a message.
    def upload_banner(channel, io)
      raise ArgumentError, "channel required" if channel.nil?
      raise ArgumentError, "io required" if io.nil?

      youtube_channel_id = extract_youtube_channel_id(channel)

      # Step 1 — upload the bytes. The `channelBanners.insert` call
      # only carries the file; `channel_id` is "derived from the
      # security context of the requestor" per the gem's docs, so
      # we leave it nil.
      insert_url = perform("channelBanners.insert", "POST") do
        svc = data_service
        content_type = io.respond_to?(:content_type) ? io.content_type : "image/jpeg"
        resource = Google::Apis::YoutubeV3::ChannelBannerResource.new
        response = svc.insert_channel_banner(
          resource,
          upload_source: io,
          content_type: content_type
        )
        # The Google gem returns a ChannelBannerResource struct;
        # `url` carries the opaque token we feed back into
        # channels.update on Step 2.
        struct = symbolize_struct(response)
        struct[:url]
      end

      if insert_url.to_s.strip.empty?
        raise Youtube::PermanentError, "channelBanners.insert returned no banner url"
      end

      # Step 2 — publish the banner by patching brandingSettings.
      # Read-modify-write the same way `#update_channel` does so we
      # don't blank out the channel section siblings (title /
      # description / country / etc.). The image section only
      # carries `banner_external_url`, so a fresh
      # ChannelSettings/ImageSettings pair is safe — the image
      # block isn't shared with channel-level fields.
      current_branding = read_current_branding(youtube_channel_id)

      perform("channels.update", "PUT") do
        svc = data_service
        image_settings = Google::Apis::YoutubeV3::ImageSettings.new(
          banner_external_url: insert_url
        )
        channel_settings = Google::Apis::YoutubeV3::ChannelSettings.new(**current_branding)
        branding_settings = Google::Apis::YoutubeV3::ChannelBrandingSettings.new(
          channel: channel_settings,
          image: image_settings
        )
        channel_object = Google::Apis::YoutubeV3::Channel.new(
          id: youtube_channel_id,
          branding_settings: branding_settings
        )
        response = svc.update_channel("brandingSettings", channel_object)
        normalized = normalize_channel_item(symbolize_struct(response))
        normalized[:banner_url] || insert_url
      end
    end

    # GET /youtube/v3/videos
    def videos_list(ids:, parts: %i[snippet statistics contentDetails],
                    max_results: 50, page_token: nil)
      perform("videos.list", "GET") do
        svc = data_service
        response = svc.list_videos(
          parts.map(&:to_s).join(","),
          id: Array(ids).join(","),
          max_results: max_results,
          page_token: page_token
        )
        normalize_list(response)
      end
    end

    # GET /youtube/v3/playlists
    def playlists_list(channel_id:, parts: %i[snippet],
                       max_results: 50, page_token: nil)
      perform("playlists.list", "GET") do
        svc = data_service
        response = svc.list_playlists(
          parts.map(&:to_s).join(","),
          channel_id: channel_id,
          max_results: max_results,
          page_token: page_token
        )
        normalize_list(response)
      end
    end

    # GET /youtubeAnalytics/v2/reports
    def analytics_query(ids:, metrics:, start_date:, end_date:,
                        dimensions: nil, filters: nil, sort: nil)
      perform("reports.query", "GET") do
        svc = analytics_service
        response = svc.query_report(
          ids: ids,
          start_date: start_date,
          end_date: end_date,
          metrics: Array(metrics).join(","),
          dimensions: dimensions ? Array(dimensions).join(",") : nil,
          filters: filters,
          sort: sort
        )
        normalize_analytics(response)
      end
    end

    private

    # Wrap an API-call yield block in: token-freshness, pre-call
    # quota check, retry/backoff, single audit row write.
    def perform(endpoint, http_method)
      cost = Youtube::Quota.cost_for(endpoint)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = "success"
      http_status = nil
      error_message = nil
      result = nil
      raised = nil

      begin
        ensure_token_fresh!

        if Youtube::Quota.budget_remaining(@connection) < cost
          outcome = "quota_exceeded"
          http_status = nil
          err = Youtube::QuotaExhaustedError.new(
            "daily quota exhausted (cost=#{cost}, remaining=#{Youtube::Quota.budget_remaining(@connection)})"
          )
          error_message = err.message
          raised = err
        else
          result, outcome, http_status, error_message, raised = execute_with_retry { yield }
        end
      rescue Youtube::NeedsReauthError => e
        # Token-refresh path raised needs-reauth before we made any
        # API call. Audit it as auth_failed.
        outcome = "auth_failed"
        http_status = nil
        error_message = e.message
        raised = e
      rescue Youtube::TransientError => e
        outcome = "server_error"
        http_status = nil
        error_message = e.message
        raised = e
      ensure
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
        write_audit_row(
          endpoint: endpoint,
          http_method: http_method,
          kind: KIND,
          connection: @connection,
          user: @connection.user,
          outcome: outcome,
          http_status: http_status,
          error_message: error_message,
          duration_ms: elapsed_ms
        )
      end

      raise raised if raised

      result
    end

    # Run the API-call yield with retry/backoff. Returns
    # `[result, outcome, http_status, error_message, raised_or_nil]`.
    # When `raised_or_nil` is set the caller should re-raise after
    # the audit-row write.
    def execute_with_retry
      attempts_5xx = 0
      attempts_401 = 0
      attempts_429 = 0

      loop do
        begin
          return [ yield, "success", 200, nil, nil ]
        rescue Google::Apis::AuthorizationError => e
          attempts_401 += 1
          if attempts_401 == 1
            begin
              Youtube::TokenRefresher.call(@connection)
              next
            rescue Youtube::NeedsReauthError => refresh_err
              return [ nil, "auth_failed", nil, refresh_err.message, refresh_err ]
            rescue Youtube::TransientError => refresh_err
              return [ nil, "server_error", nil, refresh_err.message, refresh_err ]
            end
          end
          @connection.update_columns(needs_reauth: true)
          err = Youtube::NeedsReauthError.new("401 after refresh: #{e.message}")
          return [ nil, "auth_failed", 401, e.message, err ]
        rescue Google::Apis::RateLimitError => e
          if quota_exhausted?(e)
            err = Youtube::QuotaExhaustedError.new("Google reported quota exhaustion: #{e.message}")
            return [ nil, "quota_exceeded", 403, e.message, err ]
          end

          attempts_429 += 1
          if attempts_429 > 1
            err = Youtube::TransientError.new("rate-limited: #{e.message}")
            return [ nil, "rate_limited", 429, e.message, err ]
          end
          sleep(retry_after_seconds(e))
          next
        rescue Google::Apis::ServerError => e
          attempts_5xx += 1
          if attempts_5xx >= MAX_5XX_ATTEMPTS
            err = Youtube::TransientError.new("5xx after #{attempts_5xx} attempts: #{e.message}")
            return [ nil, "server_error", status_from(e), e.message, err ]
          end
          sleep(backoff_seconds(attempts_5xx))
          next
        rescue Google::Apis::ClientError => e
          status = status_from(e) || 400
          if status == 403 && quota_exhausted?(e)
            err = Youtube::QuotaExhaustedError.new("403 quota exhausted: #{e.message}")
            return [ nil, "quota_exceeded", status, e.message, err ]
          elsif status == 403 && insufficient_scopes?(e)
            # Bug-fix path — the stored token's scope set no longer
            # matches the scopes the API requires (Google added
            # consent-screen scopes after this connection was minted).
            # Classify as needs-reauth so the manage page can surface
            # the [reconnect] flow instead of bubbling a hard 500.
            @connection.update_columns(needs_reauth: true)
            err = Youtube::NeedsReauthError.new(
              "insufficient authentication scopes: #{e.message}"
            )
            return [ nil, "auth_failed", status, e.message, err ]
          elsif status == 401
            attempts_401 += 1
            if attempts_401 == 1
              begin
                Youtube::TokenRefresher.call(@connection)
                next
              rescue Youtube::NeedsReauthError => refresh_err
                return [ nil, "auth_failed", nil, refresh_err.message, refresh_err ]
              end
            end
            @connection.update_columns(needs_reauth: true)
            err = Youtube::NeedsReauthError.new("401 after refresh: #{e.message}")
            return [ nil, "auth_failed", 401, e.message, err ]
          else
            err = Youtube::PermanentError.new("client error #{status}: #{e.message}")
            return [ nil, "client_error", status, e.message, err ]
          end
        rescue StandardError => e
          if network_error?(e)
            err = Youtube::TransientError.new("network error: #{e.class}: #{e.message}")
            return [ nil, "network_error", nil, e.message, err ]
          end
          raise
        end
      end
    end

    # Phase 7.5 §11c — extract the YouTube channel id (the `UC...`
    # suffix) from a `Channel`'s `channel_url`. Used by the destructive
    # write entrypoints (channels.update / watermarks.set /
    # watermarks.unset) to scope the call to the specific channel.
    def extract_youtube_channel_id(channel)
      url = channel.respond_to?(:channel_url) ? channel.channel_url.to_s : channel.to_s
      m = url.match(%r{/channel/(UC[A-Za-z0-9_-]{22})})
      raise ArgumentError, "cannot extract YouTube channel id from #{url.inspect}" if m.nil?

      m[1]
    end

    # Phase 7.5 §11c — read-modify-write phase 1. Fetches the current
    # `brandingSettings.channel` block via `channels.list`. Returns a
    # snake_case Hash containing only the keys YouTube actually
    # returned (nil-valued keys are dropped). This goes inside the
    # same `perform(...)` chokepoint as every other call so the audit
    # row + quota check + retry semantics apply.
    BRANDING_READ_KEYS = %i[title description country default_language keywords].freeze

    def read_current_branding(youtube_channel_id)
      result = perform("channels.list", "GET") do
        svc = data_service
        response = svc.list_channels(
          "brandingSettings",
          id: youtube_channel_id,
          max_results: 1
        )
        normalize_list(response)
      end

      item = result[:items].first
      return {} if item.nil?

      branding = item[:branding_settings] || {}
      branding_channel = branding[:channel] || {}

      BRANDING_READ_KEYS.each_with_object({}) do |key, h|
        value = branding_channel[key]
        h[key] = value unless value.nil?
      end
    end

    def ensure_token_fresh!
      return unless @connection.access_token_expired?

      Youtube::TokenRefresher.call(@connection)
    end

    # Phase 15 F2 — service construction (timeouts + authorization
    # adapter) is centralized in `Youtube::ServiceFactory` so all three
    # OAuth-backed clients (this one, VideosClient, VideosReader) share
    # the same bounded-timeout posture.
    def data_service
      Youtube::ServiceFactory.data_service(@connection)
    end

    def analytics_service
      Youtube::ServiceFactory.analytics_service(@connection)
    end

    # Phase 7.5 §11a — translate one channels.list#item into the
    # snake_case Hash shape Pito caches on `channels`. Tolerates a
    # nil item (minimal-mine response) and missing sub-keys (e.g.
    # `country` absent when the channel hasn't set one) by returning
    # `nil` for the corresponding key.
    def normalize_channel_item(item)
      return empty_channel_hash if item.nil?

      snippet  = item[:snippet]            || {}
      stats    = item[:statistics]         || {}
      branding = item[:branding_settings]  || {}
      branding_channel = branding[:channel] || {}
      branding_image   = branding[:image]   || {}
      thumbnails = snippet[:thumbnails] || {}
      default_thumb = thumbnails[:default] || {}

      hidden_subs = stats[:hidden_subscriber_count]

      {
        title: snippet[:title],
        handle: snippet[:custom_url],
        description: snippet[:description],
        country: snippet[:country],
        default_language: snippet[:default_language],
        keywords: branding_channel[:keywords],
        banner_url: branding_image[:banner_external_url],
        avatar_url: default_thumb[:url],
        # `watermarks.set` is a separate Data API call; the
        # `channels.list#brandingSettings` payload does NOT carry
        # watermark metadata back. Surface as nil so the caller keeps
        # any prior cached value untouched.
        watermark_url: nil,
        watermark_timing: nil,
        watermark_offset_ms: nil,
        # 11c populates fully via the edit form. The API stores the
        # links array under a different shape (varies by branding
        # version); 11a returns an empty array to keep `Channel#links`
        # validity intact post-sync.
        links: [],
        subscriber_count: stats[:subscriber_count]&.to_i,
        view_count: stats[:view_count]&.to_i,
        video_count: stats[:video_count]&.to_i,
        hidden_subscriber_count: hidden_subs ? true : false,
        published_at: snippet[:published_at]
      }
    end

    def empty_channel_hash
      {
        title: nil, handle: nil, description: nil, country: nil,
        default_language: nil, keywords: nil, banner_url: nil,
        avatar_url: nil, watermark_url: nil, watermark_timing: nil,
        watermark_offset_ms: nil, links: [], subscriber_count: nil,
        view_count: nil, video_count: nil, hidden_subscriber_count: false,
        published_at: nil
      }
    end

    def normalize_list(response)
      items = response.respond_to?(:items) ? Array(response.items) : Array(response[:items])
      next_token = response.respond_to?(:next_page_token) ? response.next_page_token : response[:next_page_token]
      {
        items: items.map { |i| symbolize_struct(i) },
        next_page_token: next_token
      }
    end

    def normalize_analytics(response)
      column_headers = response.respond_to?(:column_headers) ? Array(response.column_headers) : []
      rows = response.respond_to?(:rows) ? Array(response.rows) : []
      {
        column_headers: column_headers.map { |h| symbolize_struct(h) },
        rows: rows
      }
    end

    def symbolize_struct(value)
      case value
      when nil, true, false, Numeric, String, Symbol, Time, Date, DateTime
        value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize_struct(v) }
      when Array
        value.map { |v| symbolize_struct(v) }
      else
        if value.respond_to?(:to_h)
          symbolize_struct(value.to_h)
        else
          value
        end
      end
    end

    def status_from(error)
      return error.status_code if error.respond_to?(:status_code) && error.status_code

      if error.respond_to?(:body) && error.body.is_a?(String)
        json = JSON.parse(error.body) rescue nil
        return json.dig("error", "code") if json.is_a?(Hash)
      end
      nil
    end

    def quota_exhausted?(error)
      body = error.respond_to?(:body) ? error.body.to_s : ""
      body.include?("quotaExceeded") || body.include?("dailyLimitExceeded")
    end

    # Detect the "insufficient authentication scopes" 403 — Google
    # returns this when the stored token's scope set is missing one
    # of the scopes the called endpoint requires (e.g., the consent
    # screen gained `youtube.force-ssl` after the connection was
    # minted). Treated as a needs-reauth situation (the user must
    # re-authorize with the current scope set), not a permanent
    # failure. Match is intentionally narrow — exact substring,
    # case-insensitive — to avoid over-broadening the path.
    def insufficient_scopes?(error)
      body = error.respond_to?(:body) ? error.body.to_s : ""
      message = error.respond_to?(:message) ? error.message.to_s : ""
      haystack = "#{body}\n#{message}".downcase
      haystack.include?("insufficient authentication scopes")
    end

    def network_error?(error)
      [
        ::Errno::ECONNREFUSED, ::Errno::ETIMEDOUT, ::Errno::EHOSTUNREACH,
        ::SocketError, ::Net::OpenTimeout, ::Net::ReadTimeout, ::EOFError
      ].any? { |klass| error.is_a?(klass) }
    end

    def backoff_seconds(attempt)
      base = 2 ** (attempt - 1) # 1, 2, 4
      jitter = base * 0.2 * (rand - 0.5) * 2
      [ base + jitter, 0.05 ].max
    end

    def retry_after_seconds(error)
      header_value = error.respond_to?(:header) ? error.header.to_s.to_i : 0
      candidate = header_value > 0 ? header_value : RATE_LIMITED_DEFAULT_RETRY_AFTER
      [ candidate, 30 ].min
    end
  end
end
