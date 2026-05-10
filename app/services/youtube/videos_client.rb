require "google/apis/youtube_v3"
require "google/apis/errors"

# Phase 12 — write-side service for the destructive
# `videos.update?part=snippet,status` API (50 units). Builds the full
# `snippet` and `status` payloads from the local Video, then passes
# through any extra fields the reader returned that pito does not
# model (defaultLanguage, defaultAudioLanguage, etc.) — Note 1's
# destructive-PUT-per-part warning.
#
# The client is the dual to `Youtube::VideosReader` and uses the same
# `Youtube::Auditor`-driven 1-row-per-call discipline so the audit
# table reflects the 50-unit cost accurately.
#
# Phase 15 audit fix-forward (F1): mirrors `Youtube::Client`'s
# token-freshness contract — `ensure_token_fresh!` runs before the
# call, and a 401 mid-call triggers exactly one
# `Youtube::TokenRefresher` retry before raising `AuthRevokedError`.
# An access_token that simply expired with a healthy refresh_token
# must NOT surface as `needs_reauth: true`.
#
# Phase 15 audit fix-forward (F2): the underlying Google service is
# built via `Youtube::ServiceFactory` so HTTP timeouts are bounded.
module Youtube
  class VideosClient
    include Auditor
    include Youtube::OauthRefresh

    KIND = "oauth"
    ENDPOINT = "videos.update".freeze
    HTTP_METHOD = "PUT".freeze

    # Track the last payload the test surface can introspect. Module
    # state is per-instance — never set in production code paths.
    attr_reader :last_payload

    def initialize(youtube_connection)
      @connection = youtube_connection
    end

    # Read-modify-write: takes the local `video` and the `fresh` API
    # snapshot (returned by VideosReader#read_video). Returns the
    # parsed API response on success.
    #
    # The PUT body merges the local writable fields over the fresh
    # snapshot's `snippet` / `status` — the user's local edits ARE
    # the source of truth; everything pito doesn't model passes
    # through unchanged.
    def update_video(video, fresh:)
      payload = build_payload(video, fresh)
      @last_payload = payload

      # Phase 15 F1 — proactive refresh: if the access_token is
      # already past (or within the 60s skew of) `expires_at`, refresh
      # before issuing the call so we never burn quota on a guaranteed
      # 401. A `NeedsReauthError` here surfaces as `AuthRevokedError`
      # so the caller's existing rescue ladder still works.
      begin
        ensure_token_fresh!(@connection)
      rescue Youtube::NeedsReauthError => e
        raise Youtube::AuthRevokedError, "token refresh failed: #{e.message}"
      end

      perform do
        svc = data_service
        body = Google::Apis::YoutubeV3::Video.new(
          id: video.youtube_video_id,
          snippet: build_snippet_object(payload[:snippet]),
          status: build_status_object(payload[:status])
        )
        response = svc.update_video("snippet,status", body)
        symbolize_response(response)
      end
    end

    private

    def build_payload(video, fresh)
      fresh_snippet = (fresh.is_a?(Hash) ? fresh[:snippet] : nil) || {}
      fresh_status  = (fresh.is_a?(Hash) ? fresh[:status]  : nil) || {}

      snippet = fresh_snippet.dup
      snippet[:title]       = video.title
      snippet[:description] = video.description.to_s
      snippet[:tags]        = video.tags || []
      snippet[:categoryId]  = video.category_id

      status = fresh_status.dup
      status[:privacyStatus]            = video.privacy_status
      status[:publishAt]                = video.publish_at&.iso8601
      status[:selfDeclaredMadeForKids]  = video.self_declared_made_for_kids
      status[:containsSyntheticMedia]   = video.contains_synthetic_media

      { snippet: snippet, status: status }
    end

    def build_snippet_object(hash)
      Google::Apis::YoutubeV3::VideoSnippet.new(
        title:       hash[:title],
        description: hash[:description],
        tags:        Array(hash[:tags]),
        category_id: hash[:categoryId]
      )
    end

    def build_status_object(hash)
      Google::Apis::YoutubeV3::VideoStatus.new(
        privacy_status:               hash[:privacyStatus],
        publish_at:                   hash[:publishAt],
        self_declared_made_for_kids:  hash[:selfDeclaredMadeForKids],
        contains_synthetic_media:     hash[:containsSyntheticMedia]
      )
    end

    def perform
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = "success"
      http_status = 200
      error_message = nil
      raised = nil
      result = nil
      refreshed_once = false

      begin
        result = yield
      rescue Google::Apis::AuthorizationError => e
        # Phase 15 F1 — Mirror `Youtube::Client`: a 401 mid-call gets
        # exactly one `TokenRefresher` retry before we declare the
        # connection revoked. Healthy refresh_token + expired
        # access_token must not surface as `needs_reauth: true`.
        if !refreshed_once
          refreshed_once = true
          begin
            Youtube::TokenRefresher.call(@connection)
            retry
          rescue Youtube::NeedsReauthError => refresh_err
            outcome = "auth_failed"
            http_status = 401
            error_message = refresh_err.message
            raised = Youtube::AuthRevokedError.new("401 + refresh failed (videos.update): #{refresh_err.message}")
          rescue Youtube::TransientError => refresh_err
            outcome = "server_error"
            http_status = nil
            error_message = refresh_err.message
            raised = Youtube::ServerError.new("token refresh transient (videos.update): #{refresh_err.message}")
          end
        else
          outcome = "auth_failed"
          http_status = 401
          error_message = e.message
          raised = Youtube::AuthRevokedError.new("401 after refresh (videos.update): #{e.message}")
        end
      rescue Google::Apis::RateLimitError => e
        outcome = "quota_exceeded"
        http_status = 403
        error_message = e.message
        raised = Youtube::QuotaExhaustedError.new("rate-limited from videos.update: #{e.message}")
      rescue Google::Apis::ClientError => e
        status = status_from(e)
        outcome = if status == 403 && quota_exhausted?(e)
                    "quota_exceeded"
        else
                    "client_error"
        end
        http_status = status || 400
        error_message = e.message
        raised = if outcome == "quota_exceeded"
                   Youtube::QuotaExhaustedError.new("403 quota exhausted: #{e.message}")
        elsif status == 401
                   Youtube::AuthRevokedError.new("401 from videos.update: #{e.message}")
        else
                   Youtube::ValidationError.new(e.message)
        end
      rescue Google::Apis::ServerError => e
        outcome = "server_error"
        http_status = status_from(e)
        error_message = e.message
        raised = Youtube::ServerError.new("5xx from videos.update: #{e.message}")
      ensure
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
        write_audit_row(
          endpoint: ENDPOINT,
          http_method: HTTP_METHOD,
          kind: KIND,
          connection: @connection,
          user: @connection.user,
          outcome: outcome,
          http_status: http_status,
          error_message: error_message&.to_s,
          duration_ms: elapsed_ms
        )
      end

      raise raised if raised
      result
    end

    def data_service
      Youtube::ServiceFactory.data_service(@connection)
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

    def symbolize_response(response)
      hash = if response.is_a?(Hash)
               response
      elsif response.respond_to?(:to_h)
               response.to_h
      else
               {}
      end
      symbolize(hash)
    end

    def symbolize(value)
      case value
      when nil, true, false, Numeric, String, Symbol, Time, Date, DateTime
        value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize(v) }
      when Array
        value.map { |v| symbolize(v) }
      else
        if value.respond_to?(:to_h)
          symbolize(value.to_h)
        else
          value
        end
      end
    end
  end
end
