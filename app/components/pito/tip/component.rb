# frozen_string_literal: true

module Pito
  module Tip
    # Inline tip line used on the start screen and 404 page.
    # Renders: [!] [badge_text] — [text]
    class Component < ViewComponent::Base
      def initialize(text:,
                     badge_text: I18n.t("pito.start_screen.tip_prefix"),
                     badge_class: "font-bold text-yellow",
                     exclamation_class: "text-orange")
        @text              = text
        @badge_text        = badge_text
        @badge_class       = badge_class
        @exclamation_class = exclamation_class
      end
    end
  end
end
