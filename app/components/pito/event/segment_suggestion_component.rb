# frozen_string_literal: true

module Pito
  module Event
    # SegmentSuggestionComponent — inline sub-component rendered at the bottom
    # of any segment's content (System, Error, etc.). Displays a code snippet
    # with a ctrl+/ shortcut that populates the chatbox with the given command.
    #
    # The ctrl+/ handler is handled at the scrollback level (pito--quick-run
    # controller) and targets the last element with [data-suggestion-command]
    # in the scrollback.
    #
    # Usage inside a segment template:
    #   <%= render(Pito::Event::SegmentSuggestionComponent.new(suggestion: @suggestion)) if @suggestion %>
    #
    # Suggestion hash keys:
    #   pre        — text before the code span
    #   code       — the inline code string (e.g. "/connect")
    #   post       — text after the code span, before the separator
    #   shortcut   — keyboard hint (e.g. "ctrl+/") — rendered yellow
    #   run_label  — muted label after shortcut (e.g. "run this")
    #   run_cmd    — command populated into the chatbox on ctrl+/
    class SegmentSuggestionComponent < ViewComponent::Base
      def initialize(suggestion:)
        s          = suggestion.respond_to?(:with_indifferent_access) ? suggestion.with_indifferent_access : suggestion
        @pre       = s[:pre].to_s
        @code      = s[:code].to_s
        @post      = s[:post].to_s
        @shortcut  = s[:shortcut].to_s
        @run_label = s[:run_label].to_s
        @run_cmd   = s[:run_cmd].to_s
      end
    end
  end
end
