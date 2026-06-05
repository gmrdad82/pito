# Phase 13.2 — Analytics sync engine. Wraps the
# `google-apis-youtube_analytics_v2` gem so callers receive
# pito-shape Ruby Hashes ready for `upsert_all`.
#
# Lifecycle of one call:
#
# 1. Build the params via `Channel::Youtube::AnalyticsQueryBuilder`.
# 2. Refresh the connection's access token if needed.
# 3. Issue `reports.query` against
#    `youtubeanalytics.googleapis.com/v2/reports`.
# 4. Translate Google API errors into typed exceptions
#    (`AuthError`, `RateLimitError`, `TransientError`,
#    `PermanentError`).
# 5. Write a `youtube_api_calls` audit row (success or failure)
#    with `client_kind: 'analytics_v2'` and a payload describing
#    the dimensions / metrics queried.
# 6. Parse the rows-and-headers response shape into
#    attribute-hashes ready for the caller's upsert.
#
# Retry policy (`sidekiq_options retry: 5,
# retry_in: ...`). The client itself raises on the first
# transient failure; the job-side `perform` lets Sidekiq requeue.
require "google/apis/youtube_analytics_v2"
require "google/apis/errors"

class Channel
  module Youtube
    class AnalyticsClient
      include Channel::Youtube::OauthRefresh

      # Typed exceptions raised by the client. Each maps to a specific
      # retry-or-fail policy in the spec's error-handling matrix.
      #
      # - `AuthError`     — HTTP 401. Job sets `connection.needs_reauth = true`
      #                     and exits cleanly. Sidekiq does NOT retry.
      # - `RateLimitError` — HTTP 429. Sidekiq retries with exponential backoff.
      # - `TransientError` — HTTP 5xx, network timeouts. Sidekiq retries.
      # - `PermanentError` — HTTP 4xx other than 401/429, malformed responses.
      #                     Sidekiq does NOT retry.
      class Error          < StandardError; end
      class AuthError      < Error; end
      class RateLimitError < Error; end
      class TransientError < Error; end
      class PermanentError < Error; end

      AUDIT_KIND = "analytics_v2".freeze
      AUDIT_ENDPOINT = "reports.query".freeze

      OUTCOME_OK = "succeeded".freeze
      OUTCOME_RATE_LIMITED = "rate_limited".freeze
      OUTCOME_AUTH_FAILED = "auth_failed".freeze
      OUTCOME_FAILED = "failed".freeze

      AUDIT_KEY_OK = "youtube_analytics.query.succeeded".freeze
      AUDIT_KEY_RATE_LIMITED = "youtube_analytics.query.rate_limited".freeze
      AUDIT_KEY_AUTH_FAILED = "youtube_analytics.query.auth_failed".freeze
      AUDIT_KEY_FAILED = "youtube_analytics.query.failed".freeze

      attr_reader :connection

      def initialize(connection:)
        raise ArgumentError, "connection is required" if connection.nil?

        @connection = connection
      end

      # ----- Channel queries --------------------------------------------------

      def channel_daily(channel:, from:, to:)
        assert_channel_belongs!(channel)
        params = AnalyticsQueryBuilder.channel_daily_params(
          channel_youtube_id: youtube_channel_id_for(channel),
          from: from,
          to: to,
          monetization_enabled: monetization_enabled?
        )
        execute_query(query_label: "C1.channel_daily", params: params)
      end

      def channel_window_summary(channel:, window:, today: today_pt)
        assert_channel_belongs!(channel)
        params = AnalyticsQueryBuilder.channel_window_summary_params(
          channel_youtube_id: youtube_channel_id_for(channel),
          window: window,
          today: today,
          monetization_enabled: monetization_enabled?
        )
        execute_query(query_label: "C2.channel_window_summary", params: params)
      end

      def top_videos(channel:, window:, today: today_pt, limit: AnalyticsQueryBuilder::TOP_VIDEOS_DEFAULT_LIMIT)
        assert_channel_belongs!(channel)
        params = AnalyticsQueryBuilder.top_videos_params(
          channel_youtube_id: youtube_channel_id_for(channel),
          window: window,
          today: today,
          limit: limit
        )
        execute_query(query_label: "C3.top_videos", params: params)
      end

      def channel_geography(*)
        raise NotImplementedError,
              "C4 channel-level geography is deferred (no channel_daily_by_country table; spec 03 rolls up at query time)"
      end

      def channel_demographics(*)
        raise NotImplementedError,
              "C5 channel-level demographics is deferred (no per-channel demographics table; spec 03 rolls up at query time)"
      end

      # ----- Video queries ----------------------------------------------------

      def video_daily(video:, from:, to:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_daily_params(
          video_youtube_id: video.youtube_video_id,
          from: from, to: to,
          monetization_enabled: monetization_enabled?
        )
        execute_query(query_label: "V1.video_daily", params: params)
      end

      def video_window_summary(video:, window:, today: today_pt)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_window_summary_params(
          video_youtube_id: video.youtube_video_id,
          window: window,
          today: today,
          monetization_enabled: monetization_enabled?
        )
        execute_query(query_label: "V2.video_window_summary", params: params)
      end

      def video_by_country(video:, from:, to:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_by_country_params(
          video_youtube_id: video.youtube_video_id, from: from, to: to
        )
        execute_query(query_label: "V3.video_by_country", params: params)
      end

      def video_by_device_type(video:, from:, to:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_by_device_type_params(
          video_youtube_id: video.youtube_video_id, from: from, to: to
        )
        execute_query(query_label: "V4.video_by_device_type", params: params)
      end

      def video_by_operating_system(video:, from:, to:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_by_operating_system_params(
          video_youtube_id: video.youtube_video_id, from: from, to: to
        )
        execute_query(query_label: "V4.video_by_operating_system", params: params)
      end

      def video_by_traffic_source(video:, from:, to:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_by_traffic_source_params(
          video_youtube_id: video.youtube_video_id, from: from, to: to
        )
        execute_query(query_label: "V5.video_by_traffic_source", params: params)
      end

      def video_by_subscribed_status(video:, from:, to:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_by_subscribed_status_params(
          video_youtube_id: video.youtube_video_id, from: from, to: to
        )
        execute_query(query_label: "V6.video_by_subscribed_status", params: params)
      end

      def video_demographics(video:, from:, to:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_demographics_params(
          video_youtube_id: video.youtube_video_id, from: from, to: to
        )
        execute_query(query_label: "V8.video_demographics", params: params)
      end

      def video_retention(video:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_retention_params(
          video_youtube_id: video.youtube_video_id
        )
        execute_query(query_label: "V7.video_retention", params: params)
      end

      # Phase 26 §01g — viewer-time buckets. Pulls the day x hour viewer
      # distribution for a single video over `(from..to)`. Results are
      # returned in the YouTube channel's UTC bucket; the user-tz rollup
      # happens at query time in `Pito::Analytics::ViewerTimeRollup`.
      def video_viewer_time(video:, from:, to:)
        assert_video_belongs!(video)
        params = AnalyticsQueryBuilder.video_viewer_time_params(
          video_youtube_id: video.youtube_video_id, from: from, to: to
        )
        execute_query(query_label: "V9.video_viewer_time", params: params)
      end

      # ----- Pacific Time helper ---------------------------------------------

      # Per Q11: every nightly run anchors itself at the PT day boundary.
      def today_pt
        Time.now.in_time_zone("Pacific Time (US & Canada)").to_date
      end

      # ----- Monetization ----------------------------------------------------

      def monetization_enabled?
        AppSetting.get("monetization_enabled").to_s == "yes"
      end

      private

      # Run the query against the analytics service and translate
      # Google's response / error vocabulary into pito's typed shape.
      #
      # Phase 13 security fix-forward (F2) — a 401 mid-call triggers
      # exactly one `Channel::Youtube::TokenRefresher.call(@connection)` and
      # retries `query_report`. `needs_reauth: true` is only set when
      # the refresh itself raises `Channel::Youtube::NeedsReauthError`, or when
      # the retry attempt still surfaces a 401. The audit row reflects
      # the post-retry outcome.
      def execute_query(query_label:, params:)
        validated = guard_mutual_exclusion(params)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        outcome = OUTCOME_FAILED
        http_status = nil
        raised = nil
        result = nil

        begin
          ensure_token_fresh!(@connection)
          response = query_report_with_retry(validated)
          result = normalize_response(response)
          outcome = OUTCOME_OK
          http_status = 200
        rescue Google::Apis::AuthorizationError => e
          outcome = OUTCOME_AUTH_FAILED
          http_status = status_from(e) || 401
          @connection.update_columns(needs_reauth: true) unless @connection.needs_reauth?
          raised = AuthError.new("analytics 401 after refresh: #{e.message}")
        rescue Google::Apis::RateLimitError => e
          outcome = OUTCOME_RATE_LIMITED
          http_status = 429
          raised = RateLimitError.new("analytics 429: #{e.message}")
        rescue Google::Apis::ServerError => e
          outcome = OUTCOME_FAILED
          http_status = status_from(e)
          raised = TransientError.new("analytics 5xx: #{e.message}")
        rescue Google::Apis::ClientError => e
          status = status_from(e) || 400
          if status == 401
            outcome = OUTCOME_AUTH_FAILED
            http_status = 401
            @connection.update_columns(needs_reauth: true) unless @connection.needs_reauth?
            raised = AuthError.new("analytics 401 after refresh: #{e.message}")
          elsif status == 429
            outcome = OUTCOME_RATE_LIMITED
            http_status = 429
            raised = RateLimitError.new("analytics 429: #{e.message}")
          else
            outcome = OUTCOME_FAILED
            http_status = status
            raised = PermanentError.new("analytics #{status}: #{e.message}")
          end
        rescue Channel::Youtube::NeedsReauthError => e
          outcome = OUTCOME_AUTH_FAILED
          http_status = nil
          @connection.update_columns(needs_reauth: true) unless @connection.needs_reauth?
          raised = AuthError.new("analytics token refresh failed: #{e.message}")
        rescue Channel::Youtube::TransientError => e
          outcome = OUTCOME_FAILED
          http_status = nil
          raised = TransientError.new("analytics token refresh transient: #{e.message}")
        rescue Errno::ETIMEDOUT, ::Net::OpenTimeout, ::Net::ReadTimeout, SocketError => e
          outcome = OUTCOME_FAILED
          http_status = nil
          raised = TransientError.new("analytics network: #{e.class}: #{e.message}")
        rescue StandardError => e
          if defined?(::Faraday::TimeoutError) && e.is_a?(::Faraday::TimeoutError)
            outcome = OUTCOME_FAILED
            http_status = nil
            raised = TransientError.new("analytics faraday timeout: #{e.message}")
          else
            raise
          end
        ensure
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
          write_audit(
            query_label: query_label,
            params: validated,
            outcome: outcome,
            http_status: http_status,
            duration_ms: elapsed_ms,
            error_message: raised&.message
          )
        end

        raise raised if raised

        result
      end

      # Phase 13 security fix-forward (F2) — issue `query_report` against
      # a freshly-built analytics service. On a 401 (either
      # `Google::Apis::AuthorizationError` or `Google::Apis::ClientError`
      # with status 401), attempt `Channel::Youtube::TokenRefresher.call(@connection)`
      # exactly once and re-issue the call. A second 401 propagates up so
      # `execute_query`'s outer rescue chain marks the connection
      # `needs_reauth: true`. Refresh failures propagate as
      # `Channel::Youtube::NeedsReauthError` / `Channel::Youtube::TransientError` which are
      # already mapped by the caller.
      def query_report_with_retry(validated)
        refreshed_once = false
        begin
          analytics_service.query_report(**validated)
        rescue Google::Apis::AuthorizationError
          raise if refreshed_once

          refreshed_once = true
          Channel::Youtube::TokenRefresher.call(@connection)
          retry
        rescue Google::Apis::ClientError => e
          raise if refreshed_once || (status_from(e) || 400) != 401

          refreshed_once = true
          Channel::Youtube::TokenRefresher.call(@connection)
          retry
        end
      end

      def guard_mutual_exclusion(params)
        AnalyticsQueryBuilder.assert_compatible!(
          metrics: params[:metrics],
          dimensions: params[:dimensions]
        )
        params
      end

      # Phase 13 security fix-forward (F1) — service construction
      # (timeouts + authorization adapter) is centralized in
      # `Channel::Youtube::ServiceFactory` so all four OAuth-backed clients (this
      # one, `Channel::Youtube::Client`, `Channel::Youtube::VideosClient`,
      # `Channel::Youtube::VideosReader`) share the same bounded-timeout posture.
      def analytics_service
        Channel::Youtube::ServiceFactory.analytics_service(@connection)
      end

      # Normalize the analytics response into
      # `{ column_headers: [{name:, ...}], rows: [[...]] }`.
      def normalize_response(response)
        raise PermanentError, "analytics response missing column_headers" unless response.respond_to?(:column_headers)
        raise PermanentError, "analytics response missing rows" unless response.respond_to?(:rows)

        headers = Array(response.column_headers).map do |h|
          if h.respond_to?(:to_h)
            h.to_h.transform_keys(&:to_sym)
          else
            { name: h.to_s }
          end
        end
        rows = Array(response.rows).map { |r| Array(r) }

        if headers.empty? && rows.any?
          raise PermanentError, "analytics response: rows present without column_headers"
        end

        { column_headers: headers, rows: rows }
      end

      def write_audit(query_label:, params:, outcome:, http_status:, duration_ms:, error_message:)
        payload = {
          query_label: query_label,
          dimensions: params[:dimensions],
          metrics: params[:metrics],
          filters: params[:filters],
          start_date: params[:start_date],
          end_date: params[:end_date]
        }
        payload[:error] = error_message if error_message.present?

        return unless defined?(YoutubeApiCall) && YoutubeApiCall.respond_to?(:create!)

        YoutubeApiCall.create!(
          youtube_connection_id: @connection.id,
          client_kind: AUDIT_KIND,
          endpoint: AUDIT_ENDPOINT,
          http_method: "GET",
          units: Channel::Youtube::Quota.cost_for(AUDIT_ENDPOINT),
          outcome: outcome,
          http_status: http_status,
          error_message: payload.compact.to_json,
          duration_ms: duration_ms,
          created_at: Time.current
        )
      rescue StandardError => e
        Rails.logger.warn("[Channel::Youtube::AnalyticsClient] audit write failed: #{e.class}: #{e.message}")
      end

      def status_from(error)
        return error.status_code if error.respond_to?(:status_code) && error.status_code

        if error.respond_to?(:body) && error.body.is_a?(String)
          json = JSON.parse(error.body) rescue nil
          return json.dig("error", "code") if json.is_a?(Hash)
        end
        nil
      end

      # The connection-channel relationship is implicit via
      # `Channel.youtube_connection_id`. Defense-in-depth: refuse to call
      # the API on a channel that does not belong to this connection.
      def assert_channel_belongs!(channel)
        raise ArgumentError, "channel is required" if channel.nil?
        return if channel.youtube_connection_id == @connection.id

        raise ArgumentError,
              "channel #{channel.id} does not belong to connection #{@connection.id}"
      end

      def assert_video_belongs!(video)
        raise ArgumentError, "video is required" if video.nil?
        raise ArgumentError, "video #{video.id} has no youtube_video_id" if video.youtube_video_id.blank?

        channel = video.channel
        return if channel && channel.youtube_connection_id == @connection.id

        raise ArgumentError,
              "video #{video.id} does not belong to connection #{@connection.id}"
      end

      # The `channels` table stores `channel_url`; the YouTube API's
      # `ids:` filter uses the channel ID portion (e.g. `UCxyz...`). We
      # extract it from the URL.
      def youtube_channel_id_for(channel)
        url = channel.channel_url.to_s
        match = url.match(%r{/channel/(UC[A-Za-z0-9_-]{22})\z})
        raise ArgumentError, "unparseable channel_url: #{url.inspect}" unless match

        match[1]
      end
    end
  end
end
