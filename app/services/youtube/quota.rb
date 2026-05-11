# Phase 7 — Step B (7b-youtube-client-and-audit.md). YouTube /
# YouTube Analytics quota cost map and per-connection daily budget.
#
# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006). The
# budget is now keyed by `youtube_connection_id`; semantics survive
# unchanged.
#
# Per https://developers.google.com/youtube/v3/determine_quota_cost,
# costs are pinned to the documented unit costs (rounded up where
# the cost varies by `part`). Decision 7B-quota: per-connection
# tracking; Beta is single-install single-user so per-connection
# converges with per-install accounting.
module Youtube
  module Quota
    COSTS = {
      "channels.list"      => 1,
      "channels.update"    => 50, # Phase 7.5 §11c — channel-edit destructive PUT.
      "videos.list"        => 1,
      "videos.update"      => 50, # Phase 12 — read-modify-write sync-back cost.
      "playlists.list"     => 1,
      "playlistItems.list" => 1,
      "search.list"        => 100,
      "subscriptions.list" => 1,
      "captions.list"      => 50,
      # Phase 7.5 §11c — watermark CRUD endpoints. Both billed at 50
      # units per YouTube's documented unit cost.
      "watermarks.set"     => 50,
      "watermarks.unset"   => 50,
      # YouTube Analytics v2:
      "reports.query"      => 1,
      # OAuth2 revoke endpoint — billed at 0 (not part of YouTube
      # quota) but written to the audit table for completeness.
      "oauth2.revoke"      => 0
    }.freeze

    DEFAULT_DAILY_BUDGET_UNITS = 10_000

    module_function

    # Resolve the cost for `endpoint`. Raises
    # `Youtube::UnknownEndpointError` if the endpoint is missing —
    # treat as a programming error.
    def cost_for(endpoint)
      COSTS.fetch(endpoint.to_s) do
        raise Youtube::UnknownEndpointError, "unknown endpoint: #{endpoint.inspect}"
      end
    end

    # Configurable via `Rails.application.config.youtube_daily_budget_units`
    # so the manual-test recipe can knock it down to zero to force
    # `QuotaExhaustedError`.
    def daily_budget_units
      Rails.application.config.respond_to?(:youtube_daily_budget_units) &&
        Rails.application.config.youtube_daily_budget_units || DEFAULT_DAILY_BUDGET_UNITS
    end

    # Remaining budget for `youtube_connection` today. Sums
    # OAuth-client units only (PublicClient has its own bucket
    # under `client_kind: "public"`, deferred to a later phase).
    def budget_remaining(youtube_connection)
      used = YoutubeApiCall.today
        .where(
          youtube_connection_id: youtube_connection.id,
          client_kind: "oauth"
        )
        .sum(:units)
      daily_budget_units - used.to_i
    end
  end
end
