require "google/apis/youtube_v3"
require "google/apis/errors"

# Phase 12 — read-side service that wraps `videos.list` (1 unit) for
# the read-modify-write sync-back path. The reader returns the parsed
# YouTube response so the writer can copy through fields pito does NOT
# model (defaultLanguage, defaultAudioLanguage, etc.) — preserving
# them via the destructive PUT-per-part API.
#
# The reader honors the existing audit / quota / token-refresh
# discipline by going through `Youtube::Auditor`. It does NOT use the
# Google gem's `list_videos` directly inside `Youtube::Client` because
# the spec calls for a single-method service surface; centralizing the
# 1-unit cost in one place makes the audit row exact.
module Youtube
  class VideosReader
    include Auditor

    KIND = "oauth"
    ENDPOINT = "videos.list".freeze
    HTTP_METHOD = "GET".freeze

    def initialize(youtube_connection)
      @connection = youtube_connection
    end

    # Returns the raw API hash for the video. Raises
    # `Youtube::NotFoundError` if the video does not exist on YouTube,
    # `Youtube::AuthRevokedError` on 401, `Youtube::ServerError` on 5xx.
    # The caller (sync-back job) maps to `last_sync_error` text.
    def read_video(video)
      perform do
        svc = data_service
        response = svc.list_videos(
          "snippet,status,contentDetails",
          id: video.youtube_video_id
        )
        items = response.respond_to?(:items) ? Array(response.items) : []
        raise Youtube::NotFoundError, "video #{video.youtube_video_id} not found on YouTube" if items.empty?
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

      begin
        result = yield
      rescue Youtube::NotFoundError => e
        outcome = "client_error"
        http_status = 404
        error_message = e.message
        raised = e
      rescue Google::Apis::AuthorizationError => e
        outcome = "auth_failed"
        http_status = 401
        error_message = e.message
        raised = Youtube::AuthRevokedError.new("401 from videos.list: #{e.message}")
      rescue Google::Apis::ClientError => e
        status = status_from(e)
        outcome = "client_error"
        http_status = status || 400
        error_message = e.message
        raised = if status == 404
                   Youtube::NotFoundError.new(e.message)
        else
                   Youtube::PermanentError.new("client error #{status}: #{e.message}")
        end
      rescue Google::Apis::ServerError => e
        outcome = "server_error"
        http_status = status_from(e)
        error_message = e.message
        raised = Youtube::ServerError.new("5xx from videos.list: #{e.message}")
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
      svc = Google::Apis::YoutubeV3::YouTubeService.new
      svc.authorization = build_oauth_credentials
      svc
    end

    def build_oauth_credentials
      connection = @connection
      Class.new do
        define_method(:apply!) do |headers|
          headers["Authorization"] = "Bearer #{connection.access_token}"
        end
        define_method(:apply) do |headers|
          h = headers.dup
          apply!(h)
          h
        end
      end.new
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
