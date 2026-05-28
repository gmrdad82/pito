# frozen_string_literal: true

module Pito
  module Event
    class ConfirmationPromptComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ prompt_key:, prompt_args:, command_text: }`.
      def initialize(payload: {})
        @prompt = I18n.t(payload[:prompt_key], **payload.fetch(:prompt_args, {}))
        @command_text = payload[:command_text].to_s
      end
    end
  end
end
