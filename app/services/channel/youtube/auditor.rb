# Shared audit-row writer used by `Channel::Youtube::Client` and
# `Channel::Youtube::PublicClient`.
#
# GoogleIdentity → YoutubeConnection rename (ADR 0006).
# The audit-row column flipped to `youtube_connection_id`; this writer
# accepts the new noun (`connection:`) while preserving the one-row-
# per-logical-call discipline.
class Channel
  module Youtube
    module Auditor
      private

      # Persist a single `YoutubeApiCall` row.
      # NO-OP when the model is not loaded (schema reset dropped the table).
      def write_audit_row(endpoint:, http_method:, outcome:,
                           kind:, connection:,
                           http_status: nil, error_message: nil,
                           duration_ms: nil, user: nil)
        Pito::Stack.track("youtube", endpoint: endpoint, units: Channel::Youtube::Quota.cost_for(endpoint))

        return unless defined?(YoutubeApiCall) && YoutubeApiCall.respond_to?(:create!)

        YoutubeApiCall.create!(
          youtube_connection_id: connection&.id,
          client_kind: kind,
          endpoint: endpoint,
          http_method: http_method,
          units: Channel::Youtube::Quota.cost_for(endpoint),
          outcome: outcome,
          http_status: http_status,
          error_message: error_message&.to_s&.first(2_000),
          duration_ms: duration_ms,
          created_at: Time.current
        )
      rescue StandardError => e
        Rails.logger.warn("[Channel::Youtube::Auditor] failed to persist audit row: #{e.class}: #{e.message}")
      end
    end
  end
end
