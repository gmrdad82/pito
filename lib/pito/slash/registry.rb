# frozen_string_literal: true

module Pito
  module Slash
    class Registry
      class << self
        def register(handler_class)
          verb = handler_class.verb
          registry[verb] = handler_class
          # Also map the verb's aliases (e.g. /notifs → notifications) so the
          # dispatcher resolves them — it looks up by the raw parsed verb. Since the
          # T8.9 migration the aliases live in config (verbs.yml `aliases:`), surfaced
          # via the grammar registry's slash spec — NOT the handler's `grammar do`
          # block (deleted). Boot order guarantees Grammar::Registry is populated
          # first (config/initializers/pito.rb); when it is not (isolated unit spec)
          # the spec is nil and only the canonical verb→class mapping is recorded.
          spec = Pito::Grammar::Registry.spec(namespace: :slash, name: verb)
          Array(spec&.aliases).each { |a| registry[a.to_sym] = handler_class }
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
