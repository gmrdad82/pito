require "google/apis/youtube_v3"
require "google/apis/errors"

# Phase 12 — read-side service that wraps `videos.list` (1 unit) for
# the read-modify-write sync-back path. The reader returns the parsed
# YouTube response so the writer can copy through fields pito does NOT
# model (defaultLanguage, defaultAudioLanguage, etc.) — preserving
# them via the destructive PUT-per-part API.
#
# The reader honors the existing audit / quota / token-refresh
# discipline by going through `Channel::Youtube::Auditor`. It does NOT use the
# Google gem's `list_videos` directly inside `Channel::Youtube::Client` because
# the spec calls for a single-method service surface; centralizing the
# 1-unit cost in one place makes the audit row exact.
#
# Phase 15 audit fix-forward (F1): mirrors `Channel::Youtube::Client`'s
# token-freshness contract — `ensure_token_fresh!` runs before the
# call, and a 401 mid-call triggers exactly one
# `Channel::Youtube::TokenRefresher` retry before raising `AuthRevokedError`.
#
# Phase 15 audit fix-forward (F2): the underlying Google service is
# built via `Channel::Youtube::ServiceFactory` so HTTP timeouts are bounded.
class Channel
  module Youtube
    class VideosReader
      include Auditor
      include Channel::Youtube::OauthRefresh

      KIND = "oauth"
      ENDPOINT = "videos.list".freeze
      HTTP_METHOD = "GET".freeze

      def initialize(youtube_connection)
        @connection = youtube_connection
      end

      # Returns the raw API hash for the video. Raises
      # `Channel::Youtube::NotFoundError` if the video does not exist on YouTube,
      # `Channel::Youtube::AuthRevokedError` on 401, `Channel::Youtube::ServerError` on 5xx.
      # The caller (sync-back job) maps to `last_sync_error` text.
      def read_video(video)
        # Phase 15 F1 — proactive refresh before the GET so a stale-but-
        # refreshable access_token does not falsely surface as
        # `needs_reauth: true`. A `NeedsReauthError` here surfaces as
        # `AuthRevokedError` to keep the caller's rescue ladder consistent.
        begin
          ensure_token_fresh!(@connection)
        rescue Channel::Youtube::NeedsReauthError => e
          raise Channel::Youtube::AuthRevokedError, "token refresh failed: #{e.message}"
        end

        perform do
          svc = data_service
          response = svc.list_videos(
            "snippet,status,contentDetails",
            id: video.youtube_video_id
          )
          items = response.respond_to?(:items) ? Array(response.items) : []
          raise Channel::Youtube::NotFoundError, "video #{video.youtube_video_id} not found on YouTube" if items.empty?
          symbolize(items.first)
        end
      end

      private

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
        rescue Channel::Youtube::NotFoundError => e
          outcome = "client_error"
          http_status = 404
          error_message = e.message
          raised = e
        rescue Google::Apis::AuthorizationError => e
          # Phase 15 F1 — Mirror `Channel::Youtube::Client`: a 401 mid-call gets
          # exactly one `TokenRefresher` retry before we declare the
          # connection revoked.
          if !refreshed_once
            refreshed_once = true
            begin
              Channel::Youtube::TokenRefresher.call(@connection)
              retry
            rescue Channel::Youtube::NeedsReauthError => refresh_err
              outcome = "auth_failed"
              http_status = 401
              error_message = refresh_err.message
              raised = Channel::Youtube::AuthRevokedError.new("401 + refresh failed (videos.list): #{refresh_err.message}")
            rescue Channel::Youtube::TransientError => refresh_err
              outcome = "server_error"
              http_status = nil
              error_message = refresh_err.message
              raised = Channel::Youtube::ServerError.new("token refresh transient (videos.list): #{refresh_err.message}")
            end
          else
            outcome = "auth_failed"
            http_status = 401
            error_message = e.message
            raised = Channel::Youtube::AuthRevokedError.new("401 after refresh (videos.list): #{e.message}")
          end
        rescue Google::Apis::ClientError => e
          status = status_from(e)
          outcome = "client_error"
          http_status = status || 400
          error_message = e.message
          raised = if status == 404
                     Channel::Youtube::NotFoundError.new(e.message)
          else
                     Channel::Youtube::PermanentError.new("client error #{status}: #{e.message}")
          end
        rescue Google::Apis::ServerError => e
          outcome = "server_error"
          http_status = status_from(e)
          error_message = e.message
          raised = Channel::Youtube::ServerError.new("5xx from videos.list: #{e.message}")
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
        Channel::Youtube::ServiceFactory.data_service(@connection)
      end

      def status_from(error)
        return error.status_code if error.respond_to?(:status_code) && error.status_code
        if error.respond_to?(:body) && error.body.is_a?(String)
          json = JSON.parse(error.body) rescue nil
          return json.dig("error", "code") if json.is_a?(Hash)
        end
        nil
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
end
