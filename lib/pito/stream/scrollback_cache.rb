# frozen_string_literal: true

module Pito
  module Stream
    # L2 conversation-snapshot cache — the ASSEMBLED scrollback
    # HTML per conversation, stored in SolidCache and served on GET /chat/:uuid
    # as one cache read.
    #
    # Snapshots store the FULLY SERVED html (turn containers + L1 fragments +
    # meta-slot fills applied), so handle liveness is frozen into the snapshot —
    # which is safe because EVERY path that changes what the scrollback shows
    # flows through the Broadcaster chokepoints (broadcast_event /
    # replace_event), and each busts the snapshot. The next page load
    # reassembles from L1 fragment reads (cheap) and re-stores.
    #
    # Uniform by design (owner): a 2-message and a 100-message conversation go
    # through the same mechanism — no size gating. Write path is BUST-on-write
    # + rebuild-on-read rather than append-on-write: an append would have to
    # replicate the turn-container open/append rules and still couldn't survive
    # mutations (consumption, pending→ready), while rebuild-on-read reuses the
    # L1 layer those mutations already maintain.
    #
    # Events stay canonical; the snapshot is derived and disposable.
    module ScrollbackCache
      TTL = 1.week

      module_function

      def fetch(conversation, &assemble)
        Rails.cache.fetch(key(conversation), expires_in: TTL, &assemble)
      end

      def bust(conversation)
        return if conversation.nil?

        Rails.cache.delete(key(conversation))
      end

      def key(conversation)
        # v2 (2026-07-13): v1 snapshots predated the ai segment's fx data
        # attributes and served them stale for up to a week — bump the
        # version WHENEVER event templates change what the snapshot holds.
        "pito:scrollback:v2:#{conversation.uuid}:#{Time.zone.name}"
      end

      # The canonical scrollback assembly — identical markup to the cable path:
      # each turn opens a `#turn_<id>` container; every event renders through
      # the L1 fragment + meta-fill path.
      def assemble(events)
        events.group_by(&:turn_id).map do |turn_id, turn_events|
          inner = turn_events.map { |event| Pito::Stream::EventRenderer.render(event) }.join
          %(<div id="turn_#{turn_id}" class="pito-turn">#{inner}</div>)
        end.join
      end
    end
  end
end
