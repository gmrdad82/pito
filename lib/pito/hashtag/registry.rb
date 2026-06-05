# frozen_string_literal: true

module Pito
  module Hashtag
    class Registry
      class << self
        def register(handler_class)
          handle = handler_class.handle
          registry[handle] = handler_class
        end

        def lookup(handle)
          registry[handle.to_sym]
        end

        def size
          registry.size
        end

        def registered_handles
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
          return [] unless Pito::Hashtag.const_defined?(:Handlers)

          Pito::Hashtag::Handlers.constants
            .map { |c| Pito::Hashtag::Handlers.const_get(c) }
            .select { |c| c.is_a?(Class) && c < Pito::Hashtag::Handler && c.instance_variable_defined?(:@handle) && c.instance_variable_get(:@handle) }
        rescue NameError
          []
        end
      end
    end
  end
end
