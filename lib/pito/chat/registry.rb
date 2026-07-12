# frozen_string_literal: true

module Pito
  module Chat
    class Registry
      class << self
        def register(handler_class)
          tool = handler_class.tool
          registry[tool] = handler_class
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
          return [] unless Pito::Chat.const_defined?(:Handlers)

          Pito::Chat::Handlers.constants
            .map { |c| Pito::Chat::Handlers.const_get(c) }
            .select { |c| c.is_a?(Class) && c < Pito::Chat::Handler && c.instance_variable_defined?(:@tool) && c.instance_variable_get(:@tool) }
        rescue NameError
          []
        end
      end
    end
  end
end
