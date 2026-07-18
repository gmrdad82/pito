# frozen_string_literal: true

module Pito
  # The shared copy-to-clipboard + stage-in-chatbox WIDGET CORE — a
  # self-contained `pito--clipboard` controller wrapping the lucide copy ICON
  # button + a "Copied!" feedback span, with an optional second STAGE button
  # (fill:) that pre-fills the chatbox via `pito--chat-prefill` (stage only —
  # copies AND fills, never submits). Reused by the share-link message
  # (Pito::Share::LinkComponent, copy-only) and the AI suggestion block
  # (Pito::Event::Ai::SuggestionBlockComponent, fill: true) so the widget is
  # defined and styled in ONE place (fix the widget core, not each caller).
  #
  # Both icons wear the ACTION shimmer (pito-blue↔purple), matching every other
  # clickable link/token — NOT the old cyan. Because the icon is an SVG
  # (stroke: currentColor), the gradient-clip text shimmer can't apply, so the
  # widget's CSS animates `color` between the action base/band instead
  # (see `.pito-copy__btn` in application.css).
  class UseWidgetComponent < ViewComponent::Base
    # @param text            [String]  the exact text written to the clipboard
    #                                   AND staged into the chatbox on fill
    # @param aria_label      [String]  accessible label for the copy button
    # @param fill            [Boolean] when true, also render the STAGE button
    #                                   (copy + fill the chatbox, never submit)
    # @param fill_aria_label [String]  accessible label for the stage button
    def initialize(text:, aria_label:, fill: false, fill_aria_label: "Stage command in chatbox")
      @text            = text.to_s
      @aria_label      = aria_label.to_s
      @fill            = fill
      @fill_aria_label = fill_aria_label.to_s
    end

    attr_reader :text, :aria_label, :fill_aria_label

    def fill? = @fill
  end
end
