# frozen_string_literal: true

module Pito
  module Shimmer
    # Renders a #hashtag reply token (e.g. #chi-4450) with the blue→purple
    # shimmer (.pito-hashtag-shimmer) and a shared staggered offset
    # (Pito::Shimmer.offset_class). Distinct colour from the cyan identifier
    # shimmer so reply handles read differently from @handles / #ids.
    #
    #   render(Pito::Shimmer::HashtagTokenComponent.new(text: "#chi-4450"))
    class HashtagTokenComponent < ViewComponent::Base
      SHIMMER_CLASS = "pito-hashtag-shimmer"

      def self.css_class(text, extra: nil)
        [ SHIMMER_CLASS, Pito::Shimmer.offset_class(text), extra ].compact.join(" ")
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
