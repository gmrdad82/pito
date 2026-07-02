# frozen_string_literal: true

module Pito
  module Share
    # Cached scrollback section of the public share page (0.9.0 Phase 7):
    # intro line + the shared event (reply-suppressed) + outro line, rendered
    # once and served from SolidCache — share pages are unauthenticated and
    # may be hit by anyone, so this is a hardening win too.
    #
    # The key is CONTENT-ADDRESSED: share uuid + the event's stable payload
    # digest + the before/after counts + zone. Conversation growth or an event
    # edit changes the counts/digest → new key, old entry ages out. REVOKE
    # needs no bust: the controller resolves the Share row FIRST (missing →
    # :gone) and only live shares ever reach this cache.
    #
    # The intro/outro Copy variants freeze per key — a shared page staying
    # stable for its visitors is a feature, not a bug.
    module PageCache
      TTL = 1.week

      module_function

      def fetch(share)
        event  = share.event
        counts = Pito::Conversation::ScrollbackCount.around(
          conversation: share.conversation, position: event.position
        )
        Rails.cache.fetch(key(share, event, counts), expires_in: TTL) do
          render_scrollback(event, counts)
        end
      end

      def key(share, event, counts)
        digest = Pito::Stream::FragmentCache.digest(event)
        "pito:share:v1:#{share.uuid}:#{digest}:#{counts[:before]}:#{counts[:after]}:#{Time.zone.name}"
      end

      def render_scrollback(event, counts)
        parts = []
        parts << context_line("pito.copy.share.intro", counts[:before]) if counts[:before].positive?
        parts << Pito::Stream::EventRenderer.render_public(event)
        parts << context_line("pito.copy.share.outro", counts[:after]) if counts[:after].positive?
        parts.join
      end

      def context_line(key, count)
        ApplicationController.renderer.render(
          Pito::Event::SystemComponent.new(payload: { body: Pito::Copy.render(key, count:) }),
          layout: false
        )
      end
    end
  end
end
