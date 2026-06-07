# frozen_string_literal: true

module Pito
  module Search
    # Registry of search modules, keyed by symbol. Modules auto-register via
    # `Pito::Search::Base.search_key`. `for` lazily autoloads the conventional
    # `Pito::Search::Modules::<Key>` class on a miss (Zeitwerk-friendly).
    module Registry
      @modules = {}

      class << self
        def register(key, klass)
          @modules[key.to_sym] = klass
        end

        def for(key)
          @modules[key.to_sym] || autoload!(key)
        end

        def all
          @modules.dup
        end

        private

        def autoload!(key)
          "Pito::Search::Modules::#{key.to_s.camelize}".constantize
          @modules.fetch(key.to_sym)
        rescue NameError, KeyError
          raise KeyError, "no search module registered for #{key.inspect}"
        end
      end
    end
  end
end
