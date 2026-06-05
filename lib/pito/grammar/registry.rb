# frozen_string_literal: true

module Pito
  module Grammar
    class Registry
      class << self
        # Register a Pito::Grammar::Spec, keyed by [namespace, canonical name].
        # Also indexes alias names for specs_for_alias lookup.
        def register_spec(spec)
          specs_store[spec.namespace] ||= {}
          specs_store[spec.namespace][spec.name] = spec

          spec.aliases.each do |alias_name|
            alias_index[[ spec.namespace, alias_name.to_sym ]] = spec
          end
        end

        # Register a Pito::Grammar::Vocabulary, keyed by its name.
        def register_vocabulary(vocab)
          vocabularies_store[vocab.name.to_sym] = vocab
        end

        # Returns all Specs registered under the given namespace (empty array if none).
        def specs(namespace:)
          specs_store[namespace]&.values || []
        end

        # Returns the Spec with the exact canonical name, or nil.
        def spec(namespace:, name:)
          specs_store[namespace]&.fetch(name.to_sym, nil)
        end

        # Returns the Spec whose names (canonical + aliases) include token, or nil.
        # Accepts Symbol or String; compares as Symbols.
        def specs_for_alias(namespace:, token:)
          sym = token.to_sym

          # Check canonical names first
          found = specs_store[namespace]&.fetch(sym, nil)
          return found if found

          # Check alias index
          alias_index[[ namespace, sym ]]
        end

        # Returns the Vocabulary with the given name (accepts Symbol or String), or nil.
        def vocabulary(name)
          vocabularies_store[name.to_sym]
        end

        # Returns an Array of all registered Vocabularies.
        def vocabularies
          vocabularies_store.values
        end

        # Clears all stored specs and vocabularies (needed for test isolation).
        def reset!
          @specs_store   = nil
          @alias_index   = nil
          @vocabularies_store = nil
        end

        # Boot entry point. Composition contract must not be changed.
        def register_all!
          reset!
          Pito::Grammar::Vocabularies.register_all!(self) if defined?(Pito::Grammar::Vocabularies)
          Pito::Grammar::Specs.register_all!(self)        if defined?(Pito::Grammar::Specs)
          register_handler_specs
        end

        private

        def specs_store
          @specs_store ||= {}
        end

        def alias_index
          @alias_index ||= {}
        end

        def vocabularies_store
          @vocabularies_store ||= {}
        end

        def register_handler_specs
          [ Pito::Slash, Pito::Chat, Pito::Hashtag ].each do |ns|
            next unless ns.const_defined?(:Handlers)

            ns::Handlers.constants
              .map  { |c| ns::Handlers.const_get(c) }
              .select { |c| c.is_a?(Class) && c.respond_to?(:grammar_spec) }
              .each do |c|
                handler_spec = c.grammar_spec
                next unless handler_spec.is_a?(Pito::Grammar::Spec)

                # Do not clobber a spec already registered (e.g. by Specs.register_all!).
                next if spec(namespace: handler_spec.namespace, name: handler_spec.name)

                register_spec(handler_spec)
              end
          end
        rescue NameError
          # Namespace modules may not be defined yet — ignore gracefully
        end
      end
    end
  end
end
