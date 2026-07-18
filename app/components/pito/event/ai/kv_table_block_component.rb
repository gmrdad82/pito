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
      # wears the same coin glyphs as `show game`, date wears the house
      # DD-MM-YYYY [HH:MM] stamp (Pito::Formatter::SyncStamp). A row command
      # makes the key click-to-prefill via the established pito--chat-prefill
      # seam — UNLESS the command is a `show vid|game|channel #<id>` and the
      # key's own text leads with that `#<id>` token, in which case the id
      # token itself gets the list-cell shimmer-and-submit treatment (like
      # the vid/game list `#id` cells) and the whole-key binding is dropped.
      class KvTableBlockComponent < ViewComponent::Base
        # Mobile crush fix: a long AI-authored label inside a bare
        # `max-content` grid column has nothing capping its growth, so it
        # widens the column and squeezes the 1fr value column down to nothing
        # (never wraps — whitespace-nowrap is terminal law). Capping the KEY
        # SPAN itself at a fixed ch width (mirrors the .pito-cell-* /
        # --scalars-label-w caps used by the other detail-card kv-grids) plus
        # overflow-hidden + text-ellipsis lets it truncate instead — paired
        # with a minmax(0, max-content) column (the same
        # .pito-data-grid pattern) so the column can actually shrink to that
        # cap on a tight viewport rather than always claiming its full
        # max-content width. This OVERRIDES KeyValueRowComponent's default
        # key_class — the shared component's defaults (used by :system detail
        # cards, keybinding tables, …) are untouched.
        KEY_CLASS = "text-cyan whitespace-nowrap overflow-hidden text-ellipsis min-w-0 max-w-[20ch]"

        # A row's command is the only entity carrier (rows have no entity
        # field — see Ai::Blocks.runnable_command). Only THESE commands earn
        # the leading `#<id>` id-token treatment; any other runnable command
        # keeps today's whole-key stage-only prefill.
        SHOW_COMMAND = /\Ashow (vid|game|channel) #?\d+\z/

        # The key's own leading `#<id>` token (e.g. "#42 Elden Ring" →
        # "#42" + " Elden Ring"). No match ⇒ no id-token split, even when the
        # command matches SHOW_COMMAND — never guess an entity into a label
        # that doesn't literally carry it.
        LEADING_ID = /\A(#\d+)(.*)\z/m

        # @param rows [Array<Array>] normalized by Ai::Blocks
        def initialize(rows:)
          @rows = rows
        end

        def call
          tag.div(class: "grid grid-cols-[minmax(0,max-content)_1fr] gap-x-2 gap-y-1") do
            safe_join(@rows.map { |key, value, command| render_row(key, value, command) })
          end
        end

        private

        def render_row(key, value, command)
          render(Pito::Table::KeyValueRowComponent.new(
            key_text:    key_text(key, command),
            key_class:   KEY_CLASS,
            key_data:    key_data(key, command),
            value_text:  value_text(value),
            value_class: value_class(value)
          ))
        end

        # The row's leading-id MatchData when the command is a show-command
        # AND the key literally leads with `#<id>` — nil otherwise (the
        # single gate both key_text and key_data check, so the two always
        # agree on which rows get the split treatment).
        def id_token_match(key, command)
          return nil unless command.present? && command.match?(SHOW_COMMAND)

          key.to_s.match(LEADING_ID)
        end

        def key_text(key, command)
          match = id_token_match(key, command)
          return "#{key}:" unless match

          safe_join([
            render(Pito::Shimmer::TokenComponent.new(text: match[1], prefill: command, submit: true)),
            "#{match[2]}:"
          ])
        end

        # Whole-key stage-only prefill (today's behavior) — dropped for
        # id-token rows (the id token itself carries the binding instead) and
        # absent entirely when the row has no command (no entity guessing).
        def key_data(key, command)
          return {} if command.blank? || id_token_match(key, command)

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

        # House date format — fixes a real divergence bug (this used to be a
        # US-order, tz-ignorant "%b %-d, %Y"). Typed date values are always a
        # strictly-shaped ISO8601 or dd-mm-yyyy[ hh:mm] string (either the
        # model sent it typed already, or Ai::Blocks.kv_value promoted a
        # plain string that parsed as one — see lib/ai/blocks.rb). Renders
        # through the house Pito::Formatter::SyncStamp (DD-MM-YYYY HH:MM,
        # tz-aware) when a time component is present; date-only when it
        # isn't, rather than inventing a fake midnight.
        ISO_DATE     = /\A\d{4}-\d{2}-\d{2}\z/
        ISO_DATETIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2})?\z/
        DMY_DATE     = /\A\d{2}-\d{2}-\d{4}\z/
        DMY_DATETIME = /\A\d{2}-\d{2}-\d{4} \d{2}:\d{2}\z/

        def formatted_date(raw)
          str = raw.to_s.strip

          case str
          when ISO_DATE     then Time.zone.iso8601(str).strftime("%d-%m-%Y")
          when DMY_DATE     then Time.zone.strptime(str, "%d-%m-%Y").strftime("%d-%m-%Y")
          when ISO_DATETIME then Pito::Formatter::SyncStamp.call(Time.zone.iso8601(str))
          when DMY_DATETIME then Pito::Formatter::SyncStamp.call(Time.zone.strptime(str, "%d-%m-%Y %H:%M"))
          else str
          end
        rescue ArgumentError, TypeError
          str
        end
      end
    end
  end
end
