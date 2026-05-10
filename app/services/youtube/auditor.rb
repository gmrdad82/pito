# Phase 7 — Step B (7b-youtube-client-and-audit.md). Shared audit-row
# writer used by `Youtube::Client` and `Youtube::PublicClient`.
#
# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
# The audit-row column flipped to `youtube_connection_id`; this writer
# accepts the new noun (`connection:`) while preserving the one-row-
# per-logical-call discipline.
module Youtube
  module Auditor
    private

    # Persist a single `YoutubeApiCall` row.
    def write_audit_row(endpoint:, http_method:, outcome:,
                        kind:, connection:,
                        http_status: nil, error_message: nil,
                        duration_ms: nil, user: nil)
      YoutubeApiCall.create!(
        user_id: user&.id || connection&.user_id,
        youtube_connection_id: connection&.id,
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
