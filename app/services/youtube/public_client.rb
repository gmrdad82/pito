# Phase 7 — Step B (7b-youtube-client-and-audit.md). Skeleton of
# the public-API-key client. Phase 8 finishes the method surface;
# Phase 7 only establishes the seam so audit-table consumers
# (Phase 11 observability) can rely on a stable schema.
#
# Locked decision (7B) — public-key (unauthenticated) quota
# tracking is deferred to Phase 8. `PublicClient` in Phase 7 has
# no pre-call budget check; calls land in the audit table for
# Phase 11 to consume. The budget value itself is Phase 8's call.
require "google/apis/youtube_v3"
require "google/apis/errors"

module Youtube
  class PublicClient
    include Auditor

    KIND = "public"

    # `configured?` is the single predicate the rest of the app
    # asks before invoking a method. The constructor never raises
    # on a missing key — the predicate exists precisely so
    # callers can branch.
    def configured?
      api_key.present?
    end

    # Smoke method — exercises the audit-row path without taking
    # on the full surface of `Youtube::Client`. Phase 8 broadens
    # this to mirror the Client API.
    def channels_list(ids:, parts: %i[snippet statistics])
      raise Youtube::NotConfiguredError, "youtube public_api_key is not set" unless configured?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = "success"
      http_status = nil
      error_message = nil
      raised = nil
      result = nil

      begin
        svc = Google::Apis::YoutubeV3::YouTubeService.new
        svc.key = api_key
        response = svc.list_channels(
          parts.map(&:to_s).join(","),
          id: Array(ids).join(",")
        )
        result = normalize_list(response)
      rescue Google::Apis::Error => e
        outcome = "client_error"
        http_status = e.respond_to?(:status_code) ? e.status_code : nil
        error_message = e.message
        raised = Youtube::PermanentError.new("public_client client_error: #{e.message}")
      ensure
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
        write_audit_row(
          endpoint: "channels.list",
          http_method: "GET",
          kind: KIND,
          connection: nil,
          user: nil,
          outcome: outcome,
          http_status: http_status,
          error_message: error_message,
          duration_ms: elapsed_ms
        )
      end

      raise raised if raised

      result
    end

    private

    # Phase 29 — Unit A1. The public API key lives exclusively in
    # `Rails.application.credentials.google_oauth.api_key` again (the
    # project's configuration strategy — secrets in credentials only).
    # The AppSetting read and the dead `:youtube, :public_api_key`
    # transitional path are both gone.
    def api_key
      Rails.application.credentials.dig(:google_oauth, :api_key)
    end

    def normalize_list(response)
      items = response.respond_to?(:items) ? Array(response.items) : []
      next_token = response.respond_to?(:next_page_token) ? response.next_page_token : nil
      {
        items: items.map { |i| i.respond_to?(:to_h) ? i.to_h : i },
        next_page_token: next_token
      }
    end
  end
end
