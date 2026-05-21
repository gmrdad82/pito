# Phase 15 — Security Hardening Pass. Centralizes construction of
# the Google API service objects used by the OAuth-backed YouTube
# clients (`Channel::Youtube::Client`, `Channel::Youtube::VideosClient`,
# `Channel::Youtube::VideosReader`). Two responsibilities:
#
# 1. **HTTP timeouts.** Every service is built with bounded
#    `open_timeout_sec` / `read_timeout_sec` / `send_timeout_sec` so a
#    hung Google endpoint can never wedge a Sidekiq worker (or a Web
#    Puma thread) indefinitely. Phase 12 audit finding F2.
#
# 2. **Authorization adapter.** Wires up an authorization object that
#    reads the connection's current `access_token` at apply-time, so a
#    refresh issued mid-call (the F1 retry path) is visible on the
#    next attempt without rebuilding the service.
#
# `OPEN_TIMEOUT_SEC` and `READ_TIMEOUT_SEC` are conservative defaults
# tuned for the Data API v3 + Analytics v2 surfaces. `videos.update`
# and the analytics `reports.query` endpoint occasionally take longer
# than a typical GET, so the read timeout is generous.
require "google/apis/youtube_v3"
require "google/apis/youtube_analytics_v2"

class Channel
  module Youtube
    module ServiceFactory
      # Connection establishment must finish quickly; if it does not,
      # the upstream is effectively down and we want Sidekiq to retry.
      OPEN_TIMEOUT_SEC = 10

      # Read / send timeouts cover the slowest legitimate Google
      # responses we expect on any current endpoint.
      READ_TIMEOUT_SEC = 30
      SEND_TIMEOUT_SEC = 30

      module_function

      # Build a Data API v3 service with timeouts and an OAuth
      # authorization adapter bound to `connection`.
      def data_service(connection)
        svc = Google::Apis::YoutubeV3::YouTubeService.new
        apply_timeouts!(svc)
        svc.authorization = build_oauth_credentials(connection)
        svc
      end

      # Build an Analytics v2 service with the same defaults.
      def analytics_service(connection)
        svc = Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService.new
        apply_timeouts!(svc)
        svc.authorization = build_oauth_credentials(connection)
        svc
      end

      def apply_timeouts!(svc)
        svc.client_options.open_timeout_sec = OPEN_TIMEOUT_SEC
        svc.client_options.read_timeout_sec = READ_TIMEOUT_SEC
        svc.client_options.send_timeout_sec = SEND_TIMEOUT_SEC
        svc
      end

      # Returns a duck-typed authorization object with `apply!` /
      # `apply` that pulls the connection's *current* access token at
      # call time. A refresh issued mid-call updates the connection
      # row; the next `apply!` reads the fresh token without needing
      # to rebuild the service.
      def build_oauth_credentials(connection)
        bound_connection = connection
        Class.new do
          define_method(:apply!) do |headers|
            headers["Authorization"] = "Bearer #{bound_connection.access_token}"
          end
          define_method(:apply) do |headers|
            h = headers.dup
            apply!(h)
            h
          end
        end.new
      end
    end
  end
end
