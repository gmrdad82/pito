# frozen_string_literal: true

# Wrapper over the YouTube Analytics API v2 used to fetch lifetime
# per-video metrics for the connected channel.
#
# Every Analytics API call flows through the same `perform`/chokepoint
# as `Channel::Youtube::Client` — token freshness, quota pre-check, retry/
# backoff for transient errors, and a single audit row (via `Pito::Stack.track`
# → `ApiRequest`) per logical call.
#
# Callers always receive plain snake_case Ruby Hashes; the Analytics
# API's `Google::Apis::YoutubeAnalyticsV2::QueryResponse` (column_headers +
# rows) is never leaked to callers.
#
# Quota is tracked under `client_kind: "analytics"` — a separate bucket
# from the Data API (`client_kind: "oauth"`) because the two APIs have
# independent daily quotas at Google.
#
# Lifecycle of a single call (mirrors Channel::Youtube::Client):
#   1. Resolve endpoint key + cost.
#   2. `ensure_token_fresh!` — refresh if access token expires within 60s.
#   3. Pre-call analytics quota check.
#   4. Execute via the underlying gem; wrap retry/backoff per retry policy.
#   5. Audit a single ApiRequest row (via Pito::Stack.track).
#   6. Normalize the response and return.
require "google/apis/youtube_analytics_v2"
require "google/apis/errors"

class Channel
  module Youtube
    class AnalyticsClient
      include Auditor

      KIND = "analytics"
      ENDPOINT = "analytics.reports.query"
      HTTP_METHOD = "GET"

      MAX_5XX_ATTEMPTS = 3
      RATE_LIMITED_DEFAULT_RETRY_AFTER = 5

      METRIC_NAMES = %w[views estimatedMinutesWatched subscribersGained subscribersLost].freeze
      METRIC_KEYS  = {
        "video"                    => :video_id,
        "views"                    => :views,
        "estimatedMinutesWatched"  => :estimated_minutes_watched,
        "subscribersGained"        => :subscribers_gained,
        "subscribersLost"          => :subscribers_lost
      }.freeze

      def initialize(youtube_connection)
        @connection = youtube_connection
      end

      # Fetch lifetime per-video metrics for the connected channel.
      #
      # Issues a single Analytics API `reports.query` call with
      # `dimensions: "video"` and the four standard metrics. Returns an
      # Array of Hashes, one per video row:
      #
      #   {
      #     video_id:                   String,
      #     views:                      Integer,
      #     estimated_minutes_watched:  Integer,
      #     subscribers_gained:         Integer,
      #     subscribers_lost:           Integer
      #   }
      #
      # Column-to-key mapping is resolved by header name, not position,
      # so it is robust to any column reordering the API might return.
      #
      # `channel_id` must be the channel's YouTube channel ID (e.g. "UCxxxxxxx").
      # The Analytics API `ids` filter becomes `"channel==<channel_id>"`.
      # `start_date` / `end_date` accept a Date object or a "YYYY-MM-DD"
      # String. `max_results` is capped at 200 by default (the Analytics
      # API maximum for `reports.query`).
      def top_videos(channel_id:, start_date:, end_date:, max_results: 200)
        perform(ENDPOINT, HTTP_METHOD) do
          svc = analytics_service
          response = svc.query_report(
            ids:         "channel==#{channel_id}",
            start_date:  date_string(start_date),
            end_date:    date_string(end_date),
            dimensions:  "video",
            metrics:     METRIC_NAMES.join(","),
            sort:        "-views",
            max_results: max_results
          )
          normalize_query_response(response)
        end
      end

      private

      # Wrap an API-call yield block in: token-freshness, pre-call
      # quota check, retry/backoff, single audit row write.
      # Mirrors Channel::Youtube::Client#perform exactly.
      def perform(endpoint, http_method)
        cost = Channel::Youtube::Quota.cost_for(endpoint)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        outcome = "success"
        http_status = nil
        error_message = nil
        result = nil
        raised = nil

        begin
          ensure_token_fresh!

          if Channel::Youtube::Quota.analytics_budget_remaining(@connection) < cost
            outcome = "quota_exceeded"
            http_status = nil
            err = Channel::Youtube::QuotaExhaustedError.new(
              "analytics daily quota exhausted (cost=#{cost}, remaining=#{Channel::Youtube::Quota.analytics_budget_remaining(@connection)})"
            )
            error_message = err.message
            raised = err
          else
            result, outcome, http_status, error_message, raised = execute_with_retry { yield }
          end
        rescue Channel::Youtube::NeedsReauthError => e
          outcome = "auth_failed"
          http_status = nil
          error_message = e.message
          raised = e
        rescue Channel::Youtube::TransientError => e
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
      # Mirrors Channel::Youtube::Client#execute_with_retry.
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
                Channel::Youtube::TokenRefresher.call(@connection)
                next
              rescue Channel::Youtube::NeedsReauthError => refresh_err
                return [ nil, "auth_failed", nil, refresh_err.message, refresh_err ]
              rescue Channel::Youtube::TransientError => refresh_err
                return [ nil, "server_error", nil, refresh_err.message, refresh_err ]
              end
            end
            @connection.flag_needs_reauth!
            err = Channel::Youtube::NeedsReauthError.new("401 after refresh: #{e.message}")
            return [ nil, "auth_failed", 401, e.message, err ]
          rescue Google::Apis::RateLimitError => e
            if quota_exhausted?(e)
              err = Channel::Youtube::QuotaExhaustedError.new("Google reported quota exhaustion: #{e.message}")
              return [ nil, "quota_exceeded", 403, e.message, err ]
            end

            attempts_429 += 1
            if attempts_429 > 1
              err = Channel::Youtube::TransientError.new("rate-limited: #{e.message}")
              return [ nil, "rate_limited", 429, e.message, err ]
            end
            sleep(retry_after_seconds(e))
            next
          rescue Google::Apis::ServerError => e
            attempts_5xx += 1
            if attempts_5xx >= MAX_5XX_ATTEMPTS
              err = Channel::Youtube::TransientError.new("5xx after #{attempts_5xx} attempts: #{e.message}")
              return [ nil, "server_error", status_from(e), e.message, err ]
            end
            sleep(backoff_seconds(attempts_5xx))
            next
          rescue Google::Apis::ClientError => e
            status = status_from(e) || 400
            if status == 403 && quota_exhausted?(e)
              err = Channel::Youtube::QuotaExhaustedError.new("403 quota exhausted: #{e.message}")
              return [ nil, "quota_exceeded", status, e.message, err ]
            elsif status == 401
              attempts_401 += 1
              if attempts_401 == 1
                begin
                  Channel::Youtube::TokenRefresher.call(@connection)
                  next
                rescue Channel::Youtube::NeedsReauthError => refresh_err
                  return [ nil, "auth_failed", nil, refresh_err.message, refresh_err ]
                end
              end
              @connection.flag_needs_reauth!
              err = Channel::Youtube::NeedsReauthError.new("401 after refresh: #{e.message}")
              return [ nil, "auth_failed", 401, e.message, err ]
            else
              err = Channel::Youtube::PermanentError.new("client error #{status}: #{e.message}")
              return [ nil, "client_error", status, e.message, err ]
            end
          rescue StandardError => e
            if network_error?(e)
              err = Channel::Youtube::TransientError.new("network error: #{e.class}: #{e.message}")
              return [ nil, "network_error", nil, e.message, err ]
            end
            raise
          end
        end
      end

      # Normalize a `Google::Apis::YoutubeAnalyticsV2::QueryResponse`
      # into an Array of snake_case Hashes.
      #
      # Column-to-key mapping is built from `response.column_headers`
      # by header name (not position), so it is robust to any column
      # reordering the API might return in the future.
      #
      # Returns `[]` when `response.rows` is nil or empty.
      def normalize_query_response(response)
        headers = Array(response.column_headers)
        rows    = Array(response.rows)
        return [] if headers.empty? || rows.empty?

        # Map each column position to its target Ruby key.
        col_keys = headers.each_with_index.map do |header, idx|
          key = METRIC_KEYS[header.name]
          [ idx, key ]
        end.to_h.compact

        rows.map do |row|
          col_keys.each_with_object({}) do |(idx, key), hash|
            value = row[idx]
            hash[key] = key == :video_id ? value.to_s : value.to_i
          end
        end
      end

      def ensure_token_fresh!
        return unless @connection.access_token_expired?

        Channel::Youtube::TokenRefresher.call(@connection)
      end

      def analytics_service
        Channel::Youtube::ServiceFactory.analytics_service(@connection)
      end

      # Coerce a Date, String, or anything responding to `to_s` into a
      # "YYYY-MM-DD" string as the Analytics API requires.
      def date_string(value)
        return value.strftime("%Y-%m-%d") if value.respond_to?(:strftime)

        value.to_s
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
end
