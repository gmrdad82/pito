# frozen_string_literal: true

module Pito
  module Stream
    # L1 message-fragment cache — rendered-event HTML in
    # SolidCache, keyed by a digest of the event's STABLE payload.
    #
    # Safe because everything volatile is out of the fragment by construction:
    #   * body HTML is baked at build time (builders), so re-renders are
    #     byte-identical for a given payload;
    #   * the absolute HH:MM timestamp is creation-fixed (zone rides in the
    #     key — a zone change simply re-renders);
    #   * the ONLY thing that mutates old messages — reply-handle consumption —
    #     renders through the serve-time meta slot (EventRenderer#fill_meta_slot),
    #     so `reply_consumed` is EXCLUDED from the digest and consumption never
    #     rotates or stales a fragment;
    #   * any other payload mutation (pending→ready fills, confirmation
    #     resolution) changes the digest → natural invalidation, orphans expire.
    #
    # Excluded kinds: `thinking` (spinner lifecycle) and `confirmation`
    # (processing/resolved lifecycle) — multi-state chrome, cheap to render
    # live. Events still carrying a PENDING analytics/analyze marker are
    # excluded too (they mutate per metric-land).
    #
    # Events stay canonical; this cache is derived and disposable.
    module FragmentCache
      CACHEABLE_KINDS = %w[
        echo system enhanced system_follow_up enhanced_follow_up
        confirmation_follow_up error theme_diff
      ].freeze

      # Orphaned entries (superseded digests) age out; SolidCache's LRU cap
      # bounds the store anyway.
      TTL = 1.week

      module_function

      def fetch(event, &render)
        return yield unless cacheable?(event)

        Rails.cache.fetch(key(event), expires_in: TTL, &render)
      end

      def cacheable?(event)
        return false unless event&.persisted?
        return false unless CACHEABLE_KINDS.include?(event.kind.to_s)

        !pending_marker?(event.payload)
      end

      def pending_marker?(payload)
        return false unless payload.is_a?(Hash)

        payload.dig("analytics", "status") == "pending" ||
          payload.dig("analyze", "status") == "pending"
      end

      def key(event)
        "pito:fragment:v1:#{event.kind}:#{event.id}:#{Time.zone.name}:#{digest(event)}"
      end

      def digest(event)
        Digest::SHA256.hexdigest(stable_payload(event).to_json)[0, 32]
      end

      # `reply_consumed` is served via the meta slot — the fragment is identical
      # before and after consumption, so it must NOT rotate the key.
      def stable_payload(event)
        payload = event.payload
        payload.is_a?(Hash) ? payload.except("reply_consumed") : payload
      end
    end
  end
end
