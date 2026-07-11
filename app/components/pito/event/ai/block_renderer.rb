# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # The ONE place normalized Ai::Blocks rows meet ViewComponents. Every
      # block type maps to exactly one component; anything unrecognized (a
      # payload persisted before a type existed, say) renders as its JSON in a
      # text block — never an error, never raw markup.
      module BlockRenderer
        module_function

        # timestamp: rides only on text blocks — the message's first block gets
        # it so the "HH:MM " prefix flows inline with the prose.
        def component_for(block, timestamp: nil)
          block = block.stringify_keys if block.respond_to?(:stringify_keys)

          case block["type"].to_s
          when "text"
            TextBlockComponent.new(text: block["text"], timestamp:)
          when "kv_table"
            KvTableBlockComponent.new(rows: block["rows"])
          when "table"
            TableBlockComponent.new(header: block["header"], rows: block["rows"])
          when "media"
            MediaBlockComponent.new(entity: block["entity"], id: block["id"], variant: block["variant"])
          when "sparkline", "chart", "score", "ttb"
            VizBlockComponent.new(block:)
          when "suggestion"
            SuggestionBlockComponent.new(command: block["command"], note: block["note"])
          else
            TextBlockComponent.new(text: JSON.generate(block))
          end
        end
      end
    end
  end
end
