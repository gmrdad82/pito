# frozen_string_literal: true

module Pito
  module Showcase
    # Encodes showcase suggestions to JSON safely for embedding in a
    # <script type="application/json"> tag: escapes </script> sequences so no
    # injected string can prematurely close the script element.
    module SafeJson
      module_function

      def encode(array)
        JSON.generate(array).gsub("</", "<\\/")
      end
    end
  end
end
