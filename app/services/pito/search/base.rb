# frozen_string_literal: true

module Pito
  module Search
    # Base class for a search module. A concrete module declares its key with
    # `search_key :foo` (which auto-registers it with Pito::Search::Registry) and
    # implements `#call(query:, **opts)` returning a standardized result hash:
    #
    #   { hits: [...], total: Integer, error: nil | { kind:, message: } }
    #
    # The IGDB game search (Pito::Search::Modules::IgdbGames) is the first module;
    # local DB search + a `search` chat tool are deferred (post-Video).
    class Base
      class << self
        attr_reader :search_key_value

        def search_key(key)
          @search_key_value = key.to_sym
          Registry.register(@search_key_value, self)
        end
      end

      def call(query:, **)
        raise NotImplementedError, "#{self.class} must implement #call(query:, **opts)"
      end
    end
  end
end
