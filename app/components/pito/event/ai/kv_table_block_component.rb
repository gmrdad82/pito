# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # A key/value table block inside an :ai message — one shared
      # KeyValueRowComponent per row on the same max-content grid the :system
      # detail tables use, so values align in one column across rows.
      #
      # Rows are [key, value] or [key, value, command] (normalized by
      # Ai::Blocks). A TYPED value ({"v" =>, "format" => price|date|number|
      # score}) renders right-aligned through the house formatters — price
      # wears the same coin glyphs as `show game`. A row command makes the key
      # click-to-prefill via the established pito--chat-prefill seam.
      class KvTableBlockComponent < ViewComponent::Base
        # @param rows [Array<Array>] normalized by Ai::Blocks
        def initialize(rows:)
          @rows = rows
        end

        def call
          tag.div(class: "grid grid-cols-[max-content_1fr] gap-x-2 gap-y-1") do
            safe_join(@rows.map do |key, value, command|
              render(Pito::Table::KeyValueRowComponent.new(
                key_text:    "#{key}:",
                key_data:    key_data(command),
                value_text:  value_text(value),
                value_class: value_class(value)
              ))
            end)
          end
        end

        private

        def key_data(command)
          return {} if command.blank?

          {
            "controller"                    => "pito--chat-prefill",
            "action"                        => "click->pito--chat-prefill#fill",
            "pito--chat-prefill-text-value" => command
          }
        end

        def value_class(value)
          typed?(value) ? "text-fg-dim text-right" : Pito::Table::KeyValueRowComponent::DEFAULT_VALUE_CLASS
        end

        def value_text(value)
          return value unless typed?(value)

          case value["format"]
          when "price"  then Pito::Games::PriceGlyphs.html(price_of(value["v"])).html_safe
          when "date"   then formatted_date(value["v"])
          when "number" then Pito::Formatter::CompactCount.call(value["v"].to_f.round)
          when "score"  then value["v"].to_i.to_s
          end
        end

        def typed?(value)
          value.is_a?(Hash) && value["format"].present?
        end

        def price_of(raw)
          Float(raw)
        rescue ArgumentError, TypeError
          nil
        end

        def formatted_date(raw)
          Date.parse(raw.to_s).strftime("%b %-d, %Y")
        rescue Date::Error
          raw.to_s
        end
      end
    end
  end
end
