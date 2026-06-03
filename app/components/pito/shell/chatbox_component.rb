# frozen_string_literal: true

module Pito
  module Shell
    class ChatboxComponent < ViewComponent::Base
      # @param state [Symbol] one of :default, :start — affects placeholder text.
      # @param placeholder_key [String] i18n key for a STATIC placeholder override.
      #   When nil (the default), the hint is sampled per auth state — see #placeholder.
      # @param filter [Hash, nil] optional filter context rendered as line 2.
      #   Known keys: :channel (String), :period (String).
      # @param input_data [Hash, nil] Stimulus data attributes for the text input
      #   (e.g. `{ pito__chat_form_target: "inputField" }`).
      def initialize(state: :default, placeholder_key: nil, filter: nil, input_data: nil, authenticated: nil)
        @state = state
        @placeholder_key = placeholder_key
        @filter = filter
        @input_data = input_data
        @authenticated = authenticated
      end

      # The placeholder hint. An explicit `placeholder_key` wins (static override);
      # otherwise it is sampled per auth state (see Pito::Shell::ChatboxHint).
      # `authenticated:` can be passed explicitly for out-of-request rendering
      # (e.g. Turbo Stream broadcasts); falls back to Current.session when nil.
      def placeholder
        return t(@placeholder_key) if @placeholder_key

        auth = @authenticated.nil? ? Current.session.present? : @authenticated
        Pito::Shell::ChatboxHint.sample(authenticated: auth)
      end
    end
  end
end
