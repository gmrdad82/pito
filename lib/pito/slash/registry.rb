# frozen_string_literal: true

module Pito
  module Slash
    class Registry
      class << self
        def register(handler_class)
          verb = handler_class.verb
          registry[verb] = handler_class
          # Also map the handler's grammar aliases (e.g. /notifs → notifications)
          # so the dispatcher resolves them — it looks up by the raw parsed verb.
          Array(handler_class.grammar_spec&.aliases).each { |a| registry[a.to_sym] = handler_class }
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
          return [] unless Pito::Slash.const_defined?(:Handlers)

          Pito::Slash::Handlers.constants
            .map { |c| Pito::Slash::Handlers.const_get(c) }
            .select { |c| c.is_a?(Class) && c < Pito::Slash::Handler }
        end
      end
    end
  end
end
