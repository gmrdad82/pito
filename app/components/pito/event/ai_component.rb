# frozen_string_literal: true

module Pito
  module Event
    # Renders an :ai event — the assistant's own composed answer (Flow B of the
    # ai verb). The payload is typed BLOCKS, never markup:
    #
    #   status: [String]  "pending" while the orchestrator loop runs (the tile
    #           shows only the live tool-activity slot the Broadcaster feeds),
    #           "done" once the final payload lands via replace_event.
    #   blocks: [Array<Hash>] normalized Ai::Blocks rows — each rendered by its
    #           own component through Event::Ai::BlockRenderer (the single
    #           blocks→components mapping point).
    #   prompt: [String] the owner's question (context only, not rendered).
    #
    # Chrome: the dedicated `ai` accent (purple→pito-blue gradient bar) on the
    # surface background — the same accent the chatbox wears live while an
    # `ai …` input is being typed, and the echo of an ai turn.
    class AiComponent < ViewComponent::Base
      def initialize(payload: {}, event: nil)
        payload  = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
        @payload = payload
        @event   = event
      end

      def pending?
        @payload[:status].to_s == "pending"
      end

      def blocks
        Array(@payload[:blocks])
      end

      # The reply affordance (`#a7 apply …`) — present only when the answer
      # carries suggestions and the reply hasn't been retired.
      def reply_handle
        return nil if Pito::FollowUp.consumed?(@payload)

        @payload[:reply_handle].presence
      end

      def component_for(block, timestamp: nil)
        Pito::Event::Ai::BlockRenderer.component_for(block, timestamp:)
      end

      # Whether the message can open with the timestamp inline in its first
      # block (text flows around the prefix; other block types get a
      # standalone timestamp line instead).
      def text_block?(block)
        block.respond_to?(:[]) && block["type"].to_s == "text"
      end

      def dom_id
        "event_#{@event.id}" if @event
      end

      # The live tool-activity slot's stable id — the Broadcaster's
      # broadcast_ai_status replaces this node between loop iterations.
      def status_slot_id
        "event_#{@event&.id}__ai_status"
      end

      def timestamp
        @event&.created_at
      end

      # The model that composed this answer (stamped by the orchestrator on
      # finalize) — worn as the ✨ badge. Blank for pre-stamp messages.
      def model
        @payload[:model]
      end

      # The pending tile's opening line — the model takes a beat before its
      # first tool call, so the slot never sits empty (1-or-50 dictionary).
      def handshake_line
        Pito::Copy.render("pito.copy.ai.status.handshake")
      end
    end
  end
end
