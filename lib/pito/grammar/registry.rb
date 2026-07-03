# frozen_string_literal: true

module Pito
  module Grammar
    # Singleton class-level store for grammar Specs and Vocabularies.
    # Centralises registration so every consumer (normalizer, autocomplete engine,
    # dispatcher help renderer) queries a single authoritative catalog.
    #
    # DUAL STORE
    #   Specs     — keyed by [namespace, canonical_name] (nested Hash).
    #               A second alias_index maps [namespace, alias_sym] → Spec for
    #               O(1) lookup of commands by any of their registered names.
    #   Vocabularies — keyed by name Symbol (flat Hash).
    #
    # KEY METHODS
    #   register_spec(spec)              — add a Spec; also indexes all its aliases
    #   specs_for_alias(namespace:, token:) — canonical-name lookup first, then alias
    #   register_vocabulary(vocab)       — add a Vocabulary
    #   vocabulary(name)                 — fetch a Vocabulary by name (Symbol or String)
    #
    # BOOT CONTRACT
    #   register_all! resets all stores, then populates in order:
    #     1. Pito::Grammar::Vocabularies.register_all!(self)  — static + dynamic vocabs
    #     2. ConfigSource.chat_specs                          — chat specs from verbs.yml
    #     3. ConfigSource.slash_specs                         — slash specs from verbs.yml
    #     4. register_handler_specs                           — `grammar do…end` DSL fallback
    #        (now a no-op for slash; skips any name already registered in steps 2-3).
    #   Call register_all! once at app boot (config/initializers or to_prepare).
    #   Do NOT call it from within parsers or normalizers.
    #
    # TEST ISOLATION
    #   reset! nils all three stores.  Call it in after { } hooks so each spec
    #   starts with a clean registry without polluting other tests.
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

        # Boot entry point.
        #
        # Composition order (T8.8 chat migration + T8.9 slash migration):
        #   1. Vocabularies — ALL vocabs built from verbs.yml via ConfigSource
        #      (static canonical/synonyms/fillers + dynamic resolver wiring).
        #   2. Chat specs   — built from verbs.yml via ConfigSource (every verb
        #      that declares a `chat:` branch produces one Spec).
        #   3. Slash specs  — built from verbs.yml via ConfigSource (every verb
        #      that declares a `slash:` branch). T8.9 replaced BOTH the hand-authored
        #      Ruby table (lib/pito/grammar/specs.rb) and the per-handler `grammar
        #      do…end` blocks — config is now the single source of slash grammar.
        #   4. Handler specs — the generic `grammar do…end` DSL fallback. Now a no-op
        #      for slash (config registered every slash verb in step 3, so each
        #      handler's bare spec is skipped by the already-registered guard); kept
        #      as cross-namespace infra for any future DSL-declared chat/hashtag verb.
        def register_all!
          reset!
          Pito::Grammar::Vocabularies.register_all!(self)   if defined?(Pito::Grammar::Vocabularies)
          if defined?(Pito::Grammar::ConfigSource)
            Pito::Grammar::ConfigSource.chat_specs.each  { |spec| register_spec(spec) }
            Pito::Grammar::ConfigSource.slash_specs.each { |spec| register_spec(spec) }
          end
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
