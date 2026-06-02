# frozen_string_literal: true

module Pito
  module Event
    # Confirmation — destructive action awaiting #handle confirm/cancel.
    # Orange border, no background. Promotes to ConfirmationFollowUpComponent
    # after the user responds.
    class ConfirmationComponent < ViewComponent::Base
      BRAILLE_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      # Payload shapes:
      #
      #   Destructive commands:
      #     { body:, confirmation_handle:, processing:, processing_word_index:,
      #       resolved:, outcome:, outcome_text:, authenticated: }
      #
      #   Legacy demo path (NeedsConfirmation result):
      #     { prompt_key:, prompt_args:, command_text: }
      #
      # @param event [Event, nil] — used for timestamp in the meta line.
      def initialize(payload: {}, event: nil)
        payload       = payload.with_indifferent_access
        @body         = payload[:body].presence ||
                        I18n.t(payload[:prompt_key].to_s, **payload.fetch(:prompt_args, {}))
        @handle       = payload[:confirmation_handle].to_s.presence
        @processing   = payload[:processing] == true || payload[:processing] == "true"
        @word_index   = payload[:processing_word_index].to_i
        @resolved     = payload[:resolved] == true || payload[:resolved] == "true"
        @outcome      = payload[:outcome].to_s.presence
        @outcome_text = payload[:outcome_text].to_s.presence
        @authenticated = payload.fetch(:authenticated, true)
        @timestamp    = event&.created_at
      end

      def processing? = @processing && !@resolved
      def resolved?   = @resolved
      def confirmed?  = @outcome == "confirmed"
      def background  = nil

      def processing_word
        words = Array(I18n.t("pito.event.thinking.confirmation.doing"))
        words[@word_index] || words.first
      end

      def braille_frames_json = BRAILLE_FRAMES.to_json
    end
  end
end
