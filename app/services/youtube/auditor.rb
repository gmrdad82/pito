# Phase 7 — Step B (7b-youtube-client-and-audit.md). Shared audit-row
# writer used by `Youtube::Client` and `Youtube::PublicClient`.
#
# One row per logical API call (final outcome). The retry loop in
# `Youtube::Client` already collapses 5xx-then-success into the
# single success row that reflects the eventual outcome.
module Youtube
  module Auditor
    private

    # Persist a single `YoutubeApiCall` row.
    def write_audit_row(endpoint:, http_method:, outcome:,
                        kind:, identity:,
                        http_status: nil, error_message: nil,
                        duration_ms: nil, user: nil)
      YoutubeApiCall.create!(
        user_id: user&.id || identity&.user_id,
        google_identity_id: identity&.id,
        client_kind: kind,
        endpoint: endpoint,
        http_method: http_method,
        units: Youtube::Quota.cost_for(endpoint),
        outcome: outcome,
        http_status: http_status,
        error_message: error_message&.to_s&.first(2_000),
        duration_ms: duration_ms,
        created_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.warn("[Youtube::Auditor] failed to persist audit row: #{e.class}: #{e.message}")
    end
  end
end
