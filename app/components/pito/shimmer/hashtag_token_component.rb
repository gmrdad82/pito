# frozen_string_literal: true

module Pito
  module Shimmer
    # Renders a #hashtag reply token (e.g. #chi-4450) as MUTED text: the
    # handle is a decorative label, not an action — the clickable reply affordance
    # lives on shift+r. No shimmer (same muted treatment as the notification count).
    #
    #   render(Pito::Shimmer::HashtagTokenComponent.new(text: "#chi-4450"))
    class HashtagTokenComponent < ViewComponent::Base
      MUTED_CLASS = "text-fg-faded"

      def self.css_class(_text, extra: nil)
        [ MUTED_CLASS, extra ].compact.join(" ")
      end

      def self.html(text, extra: nil)
        ActionController::Base.helpers.tag.span(text, class: css_class(text, extra: extra))
      end

      def initialize(text:, extra_class: nil)
        @text        = text.to_s
        @extra_class = extra_class
      end

      def call
        tag.span(@text, class: self.class.css_class(@text, extra: @extra_class))
      end
    end
  end
end
