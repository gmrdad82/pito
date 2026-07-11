# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # The ✨ model indicator pinned to an :ai message's bottom-right corner —
      # an inline Lucide `sparkles` glyph (ISC, no external fetch; stroked with
      # the AI thread's purple→pito-blue gradient, same as the accent bar) next
      # to the answering model's name. Absolutely positioned chrome: it marks
      # WHICH model composed the answer without taking part in the block flow.
      # Renders nothing for messages that predate the payload's `model` stamp.
      class ModelBadgeComponent < ViewComponent::Base
        def initialize(model:)
          @model = model.to_s
        end

        attr_reader :model

        def render?
          model.present?
        end
      end
    end
  end
end
