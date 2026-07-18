# frozen_string_literal: true

module Pito
  module Share
    # Universal follow-up handler for the share / revoke / unshare tools.
    # (`help` was REMOVED as a reply tool: every handle
    # offered it and most targets answered "no help page available"; the
    # `--help` FLAG is the surviving help surface on replies.)
    #
    # These tools work on ANY event that carries a reply_handle —
    # they are NOT added to individual handler actions_for lists. Instead,
    # ChatController#handle_follow_up forces :append mode for them, and
    # FollowUpDispatchJob short-circuits to this handler before reaching the
    # registered per-target handler.
    #
    #           Source event stays live (consume: false). Works even while loading.
    # share   — mint or reuse the Share for the source event → return the
    #           /share/:uuid URL as a :system message. Idempotent per event.
    #           Source event stays live (consume: false) so the owner can revoke later.
    # revoke / unshare — enqueue RevokeShareJob (async delete by event_id) →
    #           return a :system ack. Source event consumed (consume: true).
    #           GATED: only available when a Share record exists for the event.
    #           Replying revoke/unshare on an unshared message returns a clear error.
    class UniversalActions
      # share is always available on every reply_handle event (when shareable).
      ALWAYS_AVAILABLE = %w[share].freeze

      # revoke/unshare are only available when a Share row exists for the event.
      SHARE_REQUIRED = %w[revoke unshare].freeze

      # Full token set, derived from Pito::Dispatch::Matrix.universal_tokens
      # (the universal_reply: block in tools.yml). Used for short-circuit detection
      # in the dispatch job and controller. Replaces the former hardcoded constant.
      def self.tools
        Pito::Dispatch::Matrix.universal_tokens
      end

      # True when a typed reply action should short-circuit to UniversalActions
      # instead of the per-target handler. Universal actions never OVERRIDE a
      # tool's own declarations: a token the event's reply_target declares itself
      # routes to the tool, and a source event whose origin tool opted out
      # (`universal_reply: false` in tools.yml) is never intercepted.
      def self.intercept?(action, event:)
        token = action.to_s
        return false unless tools.include?(token)
        return false unless Pito::Dispatch::UniversalReply.allowed_for?(event)

        target = event.payload["reply_target"].to_s
        target.blank? || !Pito::FollowUp::Registry.actions_for(target).include?(token)
      end

      # The universal tools to offer for an event's reply menu. Share tools
      # are kind-gated per the
      # `kinds:` declaration in universal_reply config (only :system and :enhanced
      # for now), and further gated on resolution state.
      # Centralised so the palette (Suggestions::Engine) and the hashtag-help page
      # (HashtagHelp) stay in agreement.
      def self.tools_for(event)
        tools = []

        # Per-tool opt-out: a tool declaring `universal_reply: false` in tools.yml
        # excludes ALL of its messages from the universal set (the origin_verb
        # stamp travels on the payload — see Pito::Dispatch::UniversalReply).
        return tools if event && !Pito::Dispatch::UniversalReply.allowed_for?(event)
        # Share tools are kind-gated: the `kinds:` key on the `share` universal_reply
        # entry declares which event kinds may receive them. A nil event is the
        # generic (event-less) help page → share is shown (no revoke/unshare).
        return tools if event && !share_kind_allowed?(event)
        # An UNRESOLVED message (its thinking indicator is still spinning — e.g. an
        # analyze card mid-fan-out) is NOT shareable: sharing an in-flight message
        # would capture a half-rendered/loading state. Share tools are withheld
        # until it resolves.
        return tools if event && !resolved?(event)

        tools + ALWAYS_AVAILABLE + (event && ::Share.exists?(event_id: event.id) ? SHARE_REQUIRED : [])
      end

      # True when the event's kind is in the `kinds:` set declared for the `share`
      # universal_reply entry. A missing (nil) `kinds:` means no constraint — all
      # kinds allowed. The YAML declaration is the single source of truth (replaces
      # the former NON_SHAREABLE_KINDS Ruby constant).
      def self.share_kind_allowed?(event)
        kind_allowed?(event&.kind)
      end

      # The kind-only half of #share_kind_allowed? — no Event required, so
      # Pito::FollowUp.actions_possible? (the mint-time gate, called before any
      # Event row exists) can reuse the SAME `universal_reply.share.kinds:`
      # config read instead of digging it a second time.
      def self.kind_allowed?(kind)
        kinds = Pito::Dispatch::Config.data.dig(:universal_reply, :share, :kinds)
        return true if kinds.nil?

        kinds.map(&:to_s).include?(kind.to_s)
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
      # "https://your-tunnel.example") captured in the controller and threaded
      # through FollowUpDispatchJob — so the minted /share URL points at the host
      # the owner is actually using (NOT the static PublicHosts.app_base, which is
      # localhost in a tunnelled dev setup). Falls back to PublicHosts.app_base
      # when absent.
      def call(source_event:, rest:, conversation:, origin: nil)
        tool = rest.to_s.strip.split(/\s+/).first.to_s.downcase

        # Enforce the per-tool opt-out server-side too: the palette already hides
        # the universal tools on an opted-out message, but a typed `#handle share`
        # must be refused just the same.
        unless Pito::Dispatch::UniversalReply.allowed_for?(source_event)
          return Pito::FollowUp::Result::Error.new(
            message_key:  "pito.copy.share.not_available",
            message_args: {}
          )
        end

        # Enforce the resolution gate server-side too (the palette hides the tool,
        # but a typed `#handle share` must also be refused while the message is
        # still loading).
        unless self.class.resolved?(source_event)
          return Pito::FollowUp::Result::Error.new(
            message_key:  "pito.copy.share.not_resolved",
            message_args: {}
          )
        end

        case tool
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
