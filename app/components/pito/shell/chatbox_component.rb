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
      # @param initial_value [String] pre-filled textarea value (restored draft).
      # @param draft_uuid [String, nil] when present, wires the pito--draft
      #   Stimulus controller + uuid value on #pito-chatbox so the JS can
      #   autosave. When nil (start screen, 404) the draft controller is omitted.
      # @param conversation_title [String, nil] when present (a user-named
      #   conversation), rendered in purple at the start of the filter row.
      # @param history [Array<String>] previously-sent input_text values (newest
      #   first, capped to ~50) exposed to the history Stimulus controller.
      #   Empty on the start screen / 404; populated on the conversation page.
      # @param suggestions [Array<String>] initial showcase suggestions to cycle
      #   in the empty + idle chatbox (pito--chat-showcase controller). The
      #   server broadcasts replacements after each turn via Broadcaster
      #   #broadcast_showcase; this param seeds the first render.
      def initialize(state: :default, placeholder_key: nil, filter: nil, input_data: nil, authenticated: nil, initial_value: "", draft_uuid: nil, conversation_title: nil, history: [], suggestions: [])
        @state = state
        @placeholder_key = placeholder_key
        @filter = filter
        @input_data = input_data
        @authenticated = authenticated
        @initial_value = initial_value.to_s
        @draft_uuid = draft_uuid
        @conversation_title = conversation_title.presence
        @history = Array(history)
        @suggestions = Array(suggestions)
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

      # Returns the suggestions catalog as a JSON string for embedding in the page.
      # Respects the same `authenticated` resolution as #placeholder.
      def catalog_json
        auth = @authenticated.nil? ? Current.session.present? : @authenticated
        Pito::Suggestions::Catalog.to_json(authenticated: auth)
      end

      # JSON-encoded showcase suggestions for embedding in the data script element.
      # Escapes </script> sequences so no suggestion string can break the tag.
      def showcase_json
        Pito::Showcase::SafeJson.encode(@suggestions)
      end
    end
  end
end
