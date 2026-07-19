# frozen_string_literal: true

module Pito
  # The shared copy-to-clipboard WIDGET CORE — a self-contained
  # `pito--clipboard` controller wrapping the lucide copy ICON button + a
  # "Copied!" feedback span. Reused by the share-link message
  # (Pito::Share::LinkComponent) and the AI suggestion block
  # (Pito::Event::Ai::SuggestionBlockComponent) so the icon is defined and
  # styled in ONE place (fix the widget core, not each caller). The
  # suggestion block's own stage-in-chatbox affordance is a separate
  # shift+u chip on the command line (Pito::Keybinding::ShortcutComponent)
  # — this widget is copy-only, no fill/stage variant.
  #
  # The icon wears the ACTION shimmer (pito-blue↔purple), matching every other
  # clickable link/token — NOT the old cyan. Because the icon is an SVG
  # (stroke: currentColor), the gradient-clip text shimmer can't apply, so the
  # widget's CSS animates `color` between the action base/band instead
  # (see `.pito-copy__btn` in application.css).
  class UseWidgetComponent < ViewComponent::Base
    # @param text       [String]  the exact text written to the clipboard
    # @param aria_label [String]  accessible label for the copy button
    def initialize(text:, aria_label:)
      @text       = text.to_s
      @aria_label = aria_label.to_s
    end

    attr_reader :text, :aria_label
  end
end
