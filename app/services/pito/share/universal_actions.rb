# frozen_string_literal: true

module Pito
  module Share
    # Universal follow-up handler for the share / revoke / unshare verbs.
    #
    # These three verbs work on ANY event that carries a reply_handle —
    # they are NOT added to individual handler actions_for lists. Instead,
    # ChatController#handle_follow_up forces :append mode for them, and
    # FollowUpDispatchJob short-circuits to this handler before reaching the
    # registered per-target handler.
    #
    # share   — mint or reuse the Share for the source event → return the
    #           /share/:uuid URL as a :system message. Idempotent per event.
    #           Source event stays live (consume: false) so the owner can revoke later.
    # revoke / unshare — enqueue RevokeShareJob (async delete by event_id) →
    #           return a :system ack. Source event consumed (consume: true).
    #           GATED: only available when a Share record exists for the event.
    #           Replying revoke/unshare on an unshared message returns a clear error.
    class UniversalActions
      # share is always available on every reply_handle event.
      ALWAYS_AVAILABLE = %w[share].freeze

      # revoke/unshare are only available when a Share row exists for the event.
      SHARE_REQUIRED = %w[revoke unshare].freeze

      # Full set — the union used for short-circuit detection in the dispatch job.
      VERBS = (ALWAYS_AVAILABLE + SHARE_REQUIRED).freeze

      def call(source_event:, rest:, conversation:)
        verb = rest.to_s.strip.split(/\s+/).first.to_s.downcase

        case verb
        when "share"
          handle_share(source_event, conversation)
        when "revoke", "unshare"
          unless ::Share.exists?(event_id: source_event.id)
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.copy.share.not_shared",
              message_args: {}
            )
          end
          handle_revoke(source_event)
        else
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.copy.share.gone.title",
            message_args: {}
          )
        end
      end

      private

      def handle_share(event, conversation)
        share = ::Share.find_or_create_by!(event: event) do |s|
          s.conversation = conversation
        end

        url = "#{Pito::PublicHosts.app_base}/share/#{share.uuid}"

        Pito::FollowUp::Result::Append.new(
          events:  [ { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.share.shared_url", url:) } ],
          consume: false
        )
      end

      def handle_revoke(event)
        ::RevokeShareJob.perform_later(event.id)

        Pito::FollowUp::Result::Append.new(
          events:  [ { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.share.revoke_ack") } ],
          consume: true
        )
      end
    end
  end
end
