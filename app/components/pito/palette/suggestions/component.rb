# frozen_string_literal: true

module Pito
  module Palette
    module Suggestions
      class Component < ViewComponent::Base
        # @param mode [Symbol] :slash or :hashtag — controls bar accent and echo-char.
        # @param items [Array<Hash>] each with keys :label, :description, :masked.
        # @param selected_index [Integer] index of the highlighted row.
        # @param typed [String] what the user has typed so far (shown on the echo line).
        def initialize(mode:, items:, selected_index: 0, typed: "")
          @mode = mode
          @items = Array(items)
          @selected_index = selected_index
          @typed = typed
        end

        # Returns the data-accent value for the segment bar.
        def bar_accent
          @mode == :hashtag ? "cyan" : "purple"
        end

        # Returns the leading character shown on the cursor-echo line.
        def echo_char
          @mode == :hashtag ? "#" : "/"
        end

        # Returns the item's label, splitting out the ACTIVE model substring
        # (item[:model] — the additive @ai-only wire field, see
        # Pito::Suggestions::{Catalog,Engine}) into an orange accent span so
        # the rest keeps its ordinary label colour. The label carries the
        # model mention (SUPERSEDES the earlier description-side painting —
        # showing it in both places was noise). No item[:model], or the
        # substring not found inside the label, falls back to the label
        # rendered plain — never raises.
        def label_html(item)
          text  = item[:label].to_s
          model = item[:model]
          return text if model.blank?

          idx = text.index(model)
          return text unless idx

          before = text[0...idx]
          after  = text[(idx + model.length)..]
          safe_join([ before, tag.span(model, class: "text-orange"), after ])
        end
      end
    end
  end
end
