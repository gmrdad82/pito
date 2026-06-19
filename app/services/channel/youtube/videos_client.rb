require "google/apis/youtube_v3"
require "google/apis/errors"

# Write-side service for the destructive
# `videos.update?part=snippet,status` API (50 units). Builds the full
# `snippet` and `status` payloads from the local Video, then passes
# through any extra fields the reader returned that pito does not
# model (defaultLanguage, defaultAudioLanguage, etc.) — Note 1's
# destructive-PUT-per-part warning.
#
# The client is the dual to `Channel::Youtube::VideosReader` and uses the same
# `Channel::Youtube::Auditor`-driven 1-row-per-call discipline so the audit
# table reflects the 50-unit cost accurately.
#
# Mirrors `Channel::Youtube::Client`'s token-freshness contract —
# `ensure_token_fresh!` runs before the call, and a 401 mid-call triggers
# exactly one `Channel::Youtube::TokenRefresher` retry before raising
# `AuthRevokedError`. An access_token that simply expired with a healthy
# refresh_token must NOT surface as `needs_reauth: true`.
#
# The underlying Google service is built via `Channel::Youtube::ServiceFactory`
# so HTTP timeouts are bounded.
class Channel
  module Youtube
    class VideosClient
      include Auditor
      include Channel::Youtube::OauthRefresh

      KIND = "oauth"
      ENDPOINT = "videos.update".freeze
      HTTP_METHOD = "PUT".freeze
      DELETE_ENDPOINT = "videos.delete".freeze
      DELETE_HTTP_METHOD = "DELETE".freeze

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
      #
      # `fields:` optional kwarg restricts which Pito columns the writer
      # overlays on the fresh snapshot. When nil (the default),
      # the full writable set is pushed — same behavior as before. When
      # supplied as a Symbol or Array of Symbols (e.g., `fields: [:title]`),
      # only those fields are overlaid; everything else stays as the
      # YouTube-side snapshot returned.
      def update_video(video, fresh:, fields: nil)
        allowed = build_allowed_set(fields)
        parts   = parts_for(allowed)
        payload = build_payload(video, fresh, fields: fields)
        @last_payload = payload.merge(parts: parts)

        # Proactive refresh: if the access_token is already past (or within
        # the 60s skew of) `expires_at`, refresh before issuing the call so
        # we never burn quota on a guaranteed 401. A `NeedsReauthError` here
        # surfaces as `AuthRevokedError` so the caller's existing rescue
        # ladder still works.
        begin
          ensure_token_fresh!(@connection)
        rescue Channel::Youtube::NeedsReauthError => e
          raise Channel::Youtube::AuthRevokedError, "token refresh failed: #{e.message}"
        end

        perform do
          svc  = data_service
          body = Google::Apis::YoutubeV3::Video.new(id: video.youtube_video_id)
          # Only PUT the parts whose fields actually changed. A status-only
          # op (publish / unlist / schedule) sends `part=status` ALONE — we
          # never touch the snippet, so a stale/invalid categoryId on the
          # fresh snapshot can't sink the call.
          body.snippet = build_snippet_object(payload[:snippet]) if parts.include?("snippet")
          body.status  = build_status_object(payload[:status])   if parts.include?("status")
          response = svc.update_video(parts.join(","), body)
          symbolize_response(response)
        end
      end

      # Hard-delete the video on YouTube (`videos.delete`, 50 units).
      # Mirrors `update_video`'s token-freshness + `perform` audit wrapper,
      # but issues the gem's `delete_video(id)` instead of a PUT. `video`
      # only needs to respond to `youtube_video_id` — `VideoRemoteDelete`
      # passes a throwaway struct because the local row is already gone.
      def delete_video(video)
        begin
          ensure_token_fresh!(@connection)
        rescue Channel::Youtube::NeedsReauthError => e
          raise Channel::Youtube::AuthRevokedError, "token refresh failed: #{e.message}"
        end

        perform(endpoint: DELETE_ENDPOINT, http_method: DELETE_HTTP_METHOD, label: "videos.delete") do
          data_service.delete_video(video.youtube_video_id)
        end
      end

      private

      SNIPPET_FIELDS = %i[title description tags category_id].freeze
      STATUS_FIELDS  = %i[
        privacy_status publish_at
        self_declared_made_for_kids contains_synthetic_media
        embeddable public_stats_viewable
      ].freeze

      def build_payload(video, fresh, fields: nil)
        fresh_snippet = (fresh.is_a?(Hash) ? fresh[:snippet] : nil) || {}
        fresh_status  = (fresh.is_a?(Hash) ? fresh[:status]  : nil) || {}

        snippet = fresh_snippet.dup
        status  = fresh_status.dup

        allowed = build_allowed_set(fields)

        # NOTE: keys are snake_case to match BOTH the reader's `.to_h` output
        # (Google gem objects serialize snake_case) AND the gem's setters, so
        # the overlay lands on the same key the fresh snapshot already carries
        # instead of silently adding a duplicate camelCase key.
        snippet[:title]       = video.title              if allowed.include?(:title)
        snippet[:description] = video.description.to_s   if allowed.include?(:description)
        snippet[:tags]        = video.tags || []         if allowed.include?(:tags)
        snippet[:category_id] = video.category_id        if allowed.include?(:category_id)

        status[:privacy_status]              = video.privacy_status              if allowed.include?(:privacy_status)
        status[:publish_at]                  = video.publish_at                  if allowed.include?(:publish_at)
        status[:self_declared_made_for_kids] = video.self_declared_made_for_kids if allowed.include?(:self_declared_made_for_kids)
        status[:embeddable]                  = video.embeddable                  if allowed.include?(:embeddable) && video.respond_to?(:embeddable)
        status[:public_stats_viewable]       = video.public_stats_viewable       if allowed.include?(:public_stats_viewable) && video.respond_to?(:public_stats_viewable)

        { snippet: snippet, status: status }
      end

      # Which `videos.update` parts to PUT, derived from the overlaid fields.
      # Only the parts whose fields changed are sent — a destructive PUT
      # replaces each named part wholesale, so sending a part we didn't mean
      # to touch risks wiping (or, with a stale categoryId, rejecting) it.
      def parts_for(allowed)
        parts = []
        parts << "snippet" if (allowed & SNIPPET_FIELDS.to_set).any?
        parts << "status"  if (allowed & STATUS_FIELDS.to_set).any?
        parts.empty? ? %w[snippet status] : parts
      end

      # `fields: nil` → all writable fields are overlaid. Otherwise the
      # supplied list is intersected with the
      # known SNIPPET + STATUS sets; unknown / display-only field names
      # are silently ignored at this layer (the apply orchestrator has
      # already filtered to writable fields before calling).
      def build_allowed_set(fields)
        if fields.nil?
          (SNIPPET_FIELDS + STATUS_FIELDS).to_set
        else
          Array(fields).map(&:to_sym).to_set & (SNIPPET_FIELDS + STATUS_FIELDS).to_set
        end
      end

      def build_snippet_object(hash)
        Google::Apis::YoutubeV3::VideoSnippet.new(
          title:       hash[:title],
          description: hash[:description],
          tags:        Array(hash[:tags]),
          category_id: hash[:category_id]
        )
      end

      def build_status_object(hash)
        Google::Apis::YoutubeV3::VideoStatus.new(
          privacy_status:               hash[:privacy_status],
          publish_at:                   youtube_rfc3339(hash[:publish_at]),
          self_declared_made_for_kids:  hash[:self_declared_made_for_kids],
          embeddable:                   hash[:embeddable],
          public_stats_viewable:        hash[:public_stats_viewable],
          license:                      hash[:license]
        )
      end

      # YouTube requires publishAt as an RFC3339 timestamp. A local Time /
      # TimeWithZone serializes via #to_s ("2026-06-19 03:10:10 +0200"), which
      # YouTube rejects as invalidPublishAt — so coerce Times to UTC RFC3339
      # ("2026-06-19T01:10:10Z"). Strings (already RFC3339, e.g. from a fresh API
      # snapshot) and nil pass through unchanged.
      def youtube_rfc3339(value)
        value.respond_to?(:utc) ? value.utc.iso8601 : value
      end

      def perform(endpoint: ENDPOINT, http_method: HTTP_METHOD, label: "videos.update")
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
          # Mirror `Channel::Youtube::Client`: a 401 mid-call gets exactly one
          # `TokenRefresher` retry before we declare the connection revoked.
          # Healthy refresh_token + expired access_token must not surface as
          # `needs_reauth: true`.
          if !refreshed_once
            refreshed_once = true
            begin
              Channel::Youtube::TokenRefresher.call(@connection)
              retry
            rescue Channel::Youtube::NeedsReauthError => refresh_err
              outcome = "auth_failed"
              http_status = 401
              error_message = refresh_err.message
              raised = Channel::Youtube::AuthRevokedError.new("401 + refresh failed (#{label}): #{refresh_err.message}")
            rescue Channel::Youtube::TransientError => refresh_err
              outcome = "server_error"
              http_status = nil
              error_message = refresh_err.message
              raised = Channel::Youtube::ServerError.new("token refresh transient (#{label}): #{refresh_err.message}")
            end
          else
            outcome = "auth_failed"
            http_status = 401
            error_message = e.message
            raised = Channel::Youtube::AuthRevokedError.new("401 after refresh (#{label}): #{e.message}")
          end
        rescue Google::Apis::RateLimitError => e
          outcome = "quota_exceeded"
          http_status = 403
          error_message = e.message
          raised = Channel::Youtube::QuotaExhaustedError.new("rate-limited from #{label}: #{e.message}")
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
                     Channel::Youtube::QuotaExhaustedError.new("403 quota exhausted: #{e.message}")
          elsif status == 401
                     Channel::Youtube::AuthRevokedError.new("401 from #{label}: #{e.message}")
          else
                     Channel::Youtube::ValidationError.new(e.message)
          end
        rescue Google::Apis::ServerError => e
          outcome = "server_error"
          http_status = status_from(e)
          error_message = e.message
          raised = Channel::Youtube::ServerError.new("5xx from #{label}: #{e.message}")
        ensure
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
          write_audit_row(
            endpoint: endpoint,
            http_method: http_method,
            kind: KIND,
            connection: @connection,
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
end
