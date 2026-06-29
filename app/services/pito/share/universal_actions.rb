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

      # `origin` is the request origin (scheme + host + port, e.g.
      # "https://dev.pitomd.com") captured in the controller and threaded through
      # FollowUpDispatchJob — so the minted /share URL points at the host the owner
      # is actually using (NOT the static PublicHosts.app_base, which is localhost in
      # a tunnelled dev setup). Falls back to PublicHosts.app_base when absent.
      def call(source_event:, rest:, conversation:, origin: nil)
        verb = rest.to_s.strip.split(/\s+/).first.to_s.downcase

        case verb
        when "share"
          handle_share(source_event, conversation, origin)
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

      def handle_share(event, conversation, origin = nil)
        share = ::Share.find_or_create_by!(event: event) do |s|
          s.conversation = conversation
        end

        base = origin.presence || Pito::PublicHosts.app_base
        url  = "#{base.chomp('/')}/share/#{share.uuid}"

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
