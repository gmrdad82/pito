# frozen_string_literal: true

module Pito
  module Event
    # Confirmation — destructive action awaiting #handle confirm/cancel.
    # Orange border, no background. Transitions through three states:
    #   pending    — body + always-visible stats detail
    #   processing — Braille spinner above body (broadcasting replace)
    #   resolved   — body only
    #
    # The reply handle (the user types `#<handle> confirm` / `#<handle> cancel`)
    # rides in the single meta line — `timestamp · #handle` — and drops once the
    # reply is consumed/resolved. There is no separate usage/affordance line.
    class ConfirmationComponent < ViewComponent::Base
      def initialize(payload: {}, event: nil)
        payload        = payload.with_indifferent_access
        @body          = payload[:body].to_s.presence || ""
        @html          = payload[:html] == true || payload[:html] == "true"
        @reply_handle  = payload[:reply_handle].to_s.presence
        @reply_consumed = payload[:reply_consumed]
        @processing    = payload[:processing] == true || payload[:processing] == "true"
        @word_index    = payload[:processing_word_index].to_i
        @resolved      = payload[:resolved] == true || payload[:resolved] == "true"
        @outcome       = payload[:outcome].to_s.presence
        @outcome_text  = payload[:outcome_text].to_s.presence
        @expand_detail = Array(payload[:expand_detail])
        @timestamp     = event&.created_at
        @event         = event
      end

      def processing? = @processing && !@resolved
      def resolved?   = @resolved
      def confirmed?  = @outcome == "confirmed"
      def expandable? = @expand_detail.any? && !@resolved
      def background  = nil
      def html?       = @html

      def dom_id
        @event ? "event_#{@event.id}" : nil
      end

      def processing_word
        words = Array(I18n.t("pito.copy.thinking.confirmation.doing"))
        words[@word_index] || words.first
      end

      def braille_frames_json = Pito::Event::Concerns::BrailleFrames::FRAMES.to_json

      def reply_consumed?
        Pito::FollowUp.consumed?("reply_consumed" => @reply_consumed)
      end

      attr_reader :body, :expand_detail, :reply_handle
    end
  end
end
