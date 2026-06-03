# frozen_string_literal: true

module Pito
  module Event
    class ThinkingComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ dictionary:, word_index:, resolved:, elapsed_seconds: }`.
      # @param event [Event] the persisted event (used for timestamp, turn state).
      def initialize(payload: {}, event: nil)
        payload            = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
        @payload           = payload
        @event             = event
        @dictionary        = payload[:dictionary].to_s
        @word_index        = payload[:word_index].to_i
        @resolved          = payload[:resolved] == true || payload[:resolved] == "true"
        @elapsed_seconds   = payload[:elapsed_seconds]
      end

      def resolved?
        @resolved
      end

      def resolved_message
        return nil unless resolved?

        word    = done_word
        elapsed = @elapsed_seconds
        I18n.t("pito.event.thinking.resolved", word:, elapsed:)
      end

      def braille_frames_json
        Pito::Event::Concerns::BrailleFrames::FRAMES.to_json
      end

      def doing_words_json
        I18n.t("pito.event.thinking.#{@dictionary}.doing").to_json
      end

      def done_words_json
        I18n.t("pito.event.thinking.#{@dictionary}.done").to_json
      end

      def current_word
        doing_words[@word_index] || doing_words.first
      end

      def dom_id
        @event ? "event_#{@event.id}" : nil
      end

      private

      def doing_words
        Array(I18n.t("pito.event.thinking.#{@dictionary}.doing"))
      end

      def done_word
        Array(I18n.t("pito.event.thinking.#{@dictionary}.done"))[@word_index] || doing_words.first
      end
    end
  end
end
