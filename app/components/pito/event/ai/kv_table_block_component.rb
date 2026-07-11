# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # A key/value table block inside an :ai message — one shared
      # KeyValueRowComponent per row, dim keys, default values.
      class KvTableBlockComponent < ViewComponent::Base
        # @param rows [Array<Array(String, String)>] normalized by Ai::Blocks
        def initialize(rows:)
          @rows = rows
        end

        def call
          tag.div(class: "flex flex-col gap-0.5") do
            safe_join(@rows.map do |key, value|
              tag.div(class: "flex gap-4") do
                render(Pito::Table::KeyValueRowComponent.new(key_text: "#{key}:", value_text: value))
              end
            end)
          end
        end
      end
    end
  end
end
