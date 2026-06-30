# frozen_string_literal: true

module Pito
  module Shell
    # Renders the conversation scroll-nav: a TOP pill and a BOTTOM pill that
    # float (fixed) over the conversation column showing how many messages are
    # above / below the current scroll position.  Both pills are hidden by
    # default; the pito--scroll-nav Stimulus controller shows and hides them as
    # the user scrolls #pito-scrollback.
    #
    # Each pill contains (left → right on one line):
    #   • a count span — left empty; JS writes the interpolated count variant
    #   • a YELLOW clickable shimmer token ("ctrl+home" / "ctrl+end") — the
    #     sole click target; clicking scrolls to top / bottom of the scrollback
    #   • the 1-variant jump copy ("jump to the start" / "jump to the end")
    #
    # The 50-variant count templates are emitted as a JSON array on the
    # controller root so the JS can pick one at random per display cycle and
    # interpolate %{count} / %{direction} client-side.
    class ScrollNavComponent < ViewComponent::Base
      # Server-rendered jump label for the top pill (1-variant copy, always safe).
      def jump_to_start
        Pito::Copy.render("pito.copy.scrollback_nav.jump_to_start")
      end

      # Server-rendered jump label for the bottom pill (1-variant copy, always safe).
      def jump_to_end
        Pito::Copy.render("pito.copy.scrollback_nav.jump_to_end")
      end

      # All 50 count-variant template strings as a JSON array, for the JS
      # controller to interpolate %{count} / %{direction} at runtime.
      def count_variants_json
        raw = I18n.t("pito.copy.scrollback_nav.count", raise: true)
        Array(raw).to_json
      end

      # Yellow (clickable) shimmer CSS class for the jump token span.
      # `clickable: true` selects the YELLOW pito-kbd-shimmer (not cyan).
      def token_class(text)
        Pito::Shimmer::TokenComponent.css_class(text, clickable: true)
      end
    end
  end
end
