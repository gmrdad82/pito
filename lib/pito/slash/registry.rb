# frozen_string_literal: true

module Pito
  module Slash
    class Registry
      class << self
        def register(handler_class)
          tool = handler_class.tool
          registry[tool] = handler_class
          # Also map the tool's aliases (e.g. /notifs → notifications) so the
          # dispatcher resolves them — it looks up by the raw parsed tool. The
          # aliases live in config (tools.yml `aliases:`), surfaced
          # via the grammar registry's slash spec — NOT the handler's `grammar do`
          # block (deleted). Boot order guarantees Grammar::Registry is populated
          # first (config/initializers/pito.rb); when it is not (isolated unit spec)
          # the spec is nil and only the canonical tool→class mapping is recorded.
          spec = Pito::Grammar::Registry.spec(namespace: :slash, name: tool)
          Array(spec&.aliases).each { |a| registry[a.to_sym] = handler_class }
        end

        def lookup(tool)
          registry[tool.to_sym]
        end

        def size
          registry.size
        end

        def registered_tools
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
