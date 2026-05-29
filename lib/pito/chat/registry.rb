# frozen_string_literal: true

module Pito
  module Chat
    class Registry
      class << self
        def register(handler_class)
          verb = handler_class.verb
          registry[verb] = handler_class
        end

        def lookup(verb)
          registry[verb.to_sym]
        end

        def size
          registry.size
        end

        def registered_verbs
          registry.keys
        end

        def register_all!
          handlers.each { |h| register(h) }
        end

        private

        def registry
          @registry ||= {}
        end

        def handlers
          return [] unless Pito::Chat.const_defined?(:Handlers)

          Pito::Chat::Handlers.constants
            .map { |c| Pito::Chat::Handlers.const_get(c) }
            .select { |c| c.is_a?(Class) && c < Pito::Chat::Handler && c.instance_variable_defined?(:@verb) && c.instance_variable_get(:@verb) }
        rescue NameError
          []
        end
      end
    end
  end
end
