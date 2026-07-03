# frozen_string_literal: true

module Pito
  module Share
    # Universal follow-up handler for the help / share / revoke / unshare verbs.
    #
    # These verbs work on ANY event that carries a reply_handle —
    # they are NOT added to individual handler actions_for lists. Instead,
    # ChatController#handle_follow_up forces :append mode for them, and
    # FollowUpDispatchJob short-circuits to this handler before reaching the
    # registered per-target handler.
    #
    # help    — render the event's target HashtagHelp page as a :system message.
    #           Source event stays live (consume: false). Works even while loading.
    # share   — mint or reuse the Share for the source event → return the
    #           /share/:uuid URL as a :system message. Idempotent per event.
    #           Source event stays live (consume: false) so the owner can revoke later.
    # revoke / unshare — enqueue RevokeShareJob (async delete by event_id) →
    #           return a :system ack. Source event consumed (consume: true).
    #           GATED: only available when a Share record exists for the event.
    #           Replying revoke/unshare on an unshared message returns a clear error.
    class UniversalActions
      # help is always available on EVERY reply_handle event — regardless of kind,
      # share status, or resolution state. `#<handle> help` shows the target's
      # HashtagHelp page without consuming the reply handle.
      HELP_VERBS = %w[help].freeze

      # share is always available on every reply_handle event (when shareable).
      ALWAYS_AVAILABLE = %w[share].freeze

      # revoke/unshare are only available when a Share row exists for the event.
      SHARE_REQUIRED = %w[revoke unshare].freeze

      # Full set — the union used for short-circuit detection in the dispatch job.
      VERBS = (HELP_VERBS + ALWAYS_AVAILABLE + SHARE_REQUIRED).freeze

      # Message kinds that carry NO universal share verbs. A :confirmation message
      # is an ephemeral prompt (confirm/cancel) — sharing it makes no sense
      # (owner 2026-06-29), so its reply menu shows neither share nor revoke/unshare.
      # `help` is NOT gated by this — it is offered on every kind.
      NON_SHAREABLE_KINDS = %w[confirmation].freeze

      # The universal verbs to offer for an event's reply menu. `help` is ALWAYS
      # offered on any reply_handle event. Share verbs are gated: not for
      # non-shareable kinds (e.g. confirmation) or while the message is still loading.
      # Centralised so the palette (Suggestions::Engine) and the hashtag-help page
      # (HashtagHelp) stay in agreement.
      def self.verbs_for(event)
        # help is unconditionally available on every followupable message.
        verbs = HELP_VERBS.dup

        # A :confirmation message carries NO share verbs. A nil event is the
        # generic (event-less) help page → `share` is shown (no revoke/unshare,
        # since there's no event to check for an existing Share).
        return verbs if event && NON_SHAREABLE_KINDS.include?(event.kind.to_s)
        # An UNRESOLVED message (its thinking indicator is still spinning — e.g. an
        # analyze card mid-fan-out) is NOT shareable: sharing an in-flight message
        # would capture a half-rendered/loading state. Share verbs are withheld
        # until it resolves (owner 2026-07-01). help remains available (read-only).
        return verbs if event && !resolved?(event)

        verbs + ALWAYS_AVAILABLE + (event && ::Share.exists?(event_id: event.id) ? SHARE_REQUIRED : [])
      end

      # True when the message is done rendering — i.e. it has no still-spinning
      # thinking indicator. A thinking event links to its message via
      # payload["for_event_id"] (stamped by the Finalizer); the message is resolved
      # once that indicator's payload["resolved"] is true. A message with NO linked
      # indicator (instant messages: echo, sync, …) is trivially resolved.
      def self.resolved?(event)
        return true unless event

        thinking = event.turn.events
          .where(kind: :thinking)
          .where("payload->>'for_event_id' = ?", event.id.to_s)
          .first
        return true unless thinking

        thinking.payload["resolved"] == true || thinking.payload["resolved"] == "true"
      end

      # `origin` is the request origin (scheme + host + port, e.g.
      # "https://dev.pitomd.com") captured in the controller and threaded through
      # FollowUpDispatchJob — so the minted /share URL points at the host the owner
      # is actually using (NOT the static PublicHosts.app_base, which is localhost in
      # a tunnelled dev setup). Falls back to PublicHosts.app_base when absent.
      def call(source_event:, rest:, conversation:, origin: nil)
        verb = rest.to_s.strip.split(/\s+/).first.to_s.downcase

        # `help` is unconditionally available — dispatch it before the resolution
        # gate so the owner can see what verbs are available even while loading.
        return handle_help(source_event) if verb == "help"

        # Enforce the resolution gate server-side too (the palette hides the verb,
        # but a typed `#handle share` must also be refused while the message is
        # still loading) (owner 2026-07-01).
        unless self.class.resolved?(source_event)
          return Pito::FollowUp::Result::Error.new(
            message_key:  "pito.copy.share.not_resolved",
            message_args: {}
          )
        end

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

      # Render and append the HashtagHelp page for the source event's reply_target.
      # Does NOT consume the reply handle (like `--help`) so the owner can still
      # issue other verbs on the same message after viewing help.
      def handle_help(event)
        target  = event.payload["reply_target"].to_s
        payload = Pito::MessageBuilder::HashtagHelp.call(target:, event:)

        return Pito::FollowUp::Result::Error.new(
          message_key:  "pito.copy.share.help_unavailable",
          message_args: {}
        ) if payload.nil?

        Pito::FollowUp::Result::Append.new(
          events:  [ { kind: :system, payload: } ],
          consume: false
        )
      end

      def handle_share(event, conversation, origin = nil)
        share = ::Share.find_or_create_by!(event: event) do |s|
          s.conversation = conversation
        end

        base = origin.presence || Pito::PublicHosts.app_base
        url  = "#{base.chomp('/')}/share/#{share.uuid}"

        Pito::FollowUp::Result::Append.new(
          events:  [ { kind: :system, payload: Pito::MessageBuilder::Share::Link.call(url:) } ],
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
