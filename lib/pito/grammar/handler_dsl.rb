# frozen_string_literal: true

module Pito
  module Grammar
    # Shared DSL mixed into the singleton class of each Handler base class
    # (Pito::Slash::Handler, Pito::Chat::Handler, Pito::Hashtag::Handler).
    #
    # PURPOSE
    #   Provides the `grammar do … end` class-level DSL that lets handler
    #   authors declare slot definitions, aliases, auth requirements, and
    #   description keys without writing raw Pito::Grammar::Spec constructors.
    #
    # USAGE
    #   grammar do
    #     literal :provider, source: :config_providers
    #     enum    :state,    source: :on_off,  optional: true, when: { provider: %w[sound fx] }
    #     kv      :cfg,      source: :config_keys, optional: true, repeatable: true,
    #                        when: { provider: %w[google voyage igdb webhook] }
    #     aliases :cfg, :configuration
    #     auth    :authenticated_only
    #     description_key "pito.grammar.slash.config"
    #   end
    #
    # SLOT DECLARATIONS (produce Pito::Grammar::Slot objects)
    #   literal(name, source:, optional:, repeatable:, synonyms:)
    #     — exact-match slot; value must be a member of the named vocabulary.
    #       Also used as a sentinel to gate conditional slots via `when:`.
    #   enum(name, source:, optional:, repeatable:, introducer:, when:)
    #     — vocabulary-backed slot; resolved through Vocabulary#resolve.
    #       `introducer:` — a connective symbol (:for) that must precede the value.
    #       `when:` — Hash condition; slot is eligible only when a prior slot's
    #                 resolved value is in the allowed list.
    #   kv(name, source:, optional:, repeatable:, when:)
    #     — key=value / key:value slot; key matched against the named vocabulary.
    #   free(name, optional:)
    #     — free-text slot; slurps remaining tokens as a single string.
    #   connective(name)
    #     — reserved connector word slot (rarely used directly).
    #
    # OTHER DSL METHODS
    #   aliases(*names)     — register extra names for this command in the registry
    #   auth(value)         — :any | :authenticated_only | :unauthenticated_only
    #   description_key(key)— I18n key for the command's help blurb
    #
    # SPEC CONSTRUCTION  (grammar_spec -> Pito::Grammar::Spec | nil)
    #   When a grammar block was declared AND the handler defines a command name:
    #     → full Spec with all declared slots, aliases, auth, and description_key.
    #   When no grammar block was declared:
    #     → slash handlers that define both tool AND description_key get a bare Spec
    #       (slots: []) so they still appear in the autocomplete menu.
    #     → chat/hashtag handlers with nothing declared → nil.
    #   When the handler returns nil from tool/handle → nil (abstract base classes).
    #
    # INHERITANCE SAFETY
    #   reset_grammar_ivars! is called from each base class's `inherited` hook so
    #   the parent's grammar declaration is never accidentally inherited by a subclass.
    module HandlerDsl
      # Small builder object used inside `grammar do ... end` blocks.
      class Builder
        attr_reader :_slots, :_aliases, :_auth, :_description_key

        def initialize
          @_slots          = []
          @_aliases        = []
          @_auth           = nil
          @_description_key = nil
        end

        def enum(name, source:, optional: false, repeatable: false, introducer: nil, when: nil)
          @_slots << Pito::Grammar::Slot.new(
            name:        name,
            kind:        :enum,
            source:      source,
            optional:    optional,
            repeatable:  repeatable,
            introducer:  introducer,
            condition:   binding.local_variable_get(:when)
          )
        end

        def literal(name, source:, optional: false, repeatable: false, synonyms: [])
          @_slots << Pito::Grammar::Slot.new(
            name:       name,
            kind:       :literal,
            source:     source,
            optional:   optional,
            repeatable: repeatable,
            synonyms:   synonyms
          )
        end

        def kv(name, source:, optional: false, repeatable: false, when: nil)
          @_slots << Pito::Grammar::Slot.new(
            name:       name,
            kind:       :kv,
            source:     source,
            optional:   optional,
            repeatable: repeatable,
            condition:  binding.local_variable_get(:when)
          )
        end

        def free(name, optional: false)
          @_slots << Pito::Grammar::Slot.new(
            name:     name,
            kind:     :free,
            optional: optional
          )
        end

        def connective(name)
          @_slots << Pito::Grammar::Slot.new(
            name: name,
            kind: :connective
          )
        end

        def aliases(*names)
          @_aliases = names.flatten.map(&:to_sym)
        end

        def auth(value)
          @_auth = value
        end

        def description_key(key)
          @_description_key = key
        end
      end

      # ---------------------------------------------------------------------------
      # DSL class methods mixed into Handler base classes
      # ---------------------------------------------------------------------------

      # Declare a grammar block. Accumulates slots/aliases/auth/description_key.
      def grammar(&block)
        builder = Builder.new
        builder.instance_exec(&block)
        @_grammar_slots           = builder._slots
        @_grammar_aliases         = builder._aliases
        @_grammar_auth            = builder._auth
        @_grammar_description_key = builder._description_key
        @_grammar_declared        = true
      end

      # Direct setter alternative for slots.
      def slots=(array_of_slots)
        @_grammar_slots    = array_of_slots
        @_grammar_declared = true
      end

      # Returns a Pito::Grammar::Spec or nil.
      #
      # Resolution rules:
      #   - namespace  : derived from the enclosing module of the class
      #   - name       : `tool` for slash and chat, `handle` for hashtag
      #   - description_key: DSL override > handler's own description_key > nil
      #
      # When a grammar block was declared AND name is present → full Spec.
      # When nothing was declared:
      #   - slash handlers with both tool AND description_key → bare Spec (slots: [])
      #   - chat/hashtag with nothing declared → nil
      # When name is nil → nil.
      def grammar_spec
        ns   = _grammar_namespace
        cmd  = _grammar_command_name
        return nil if cmd.nil?

        desc_key = @_grammar_description_key ||
                   begin
                     respond_to?(:description_key) ? description_key : nil
                   rescue NotImplementedError
                     nil
                   end

        if @_grammar_declared
          Pito::Grammar::Spec.new(
            namespace:       ns,
            name:            cmd,
            aliases:         @_grammar_aliases || [],
            slots:           @_grammar_slots   || [],
            description_key: desc_key,
            auth:            @_grammar_auth || :any
          )
        elsif ns == :slash
          # Bare spec only for slash handlers that have both tool and description_key.
          return nil unless desc_key

          Pito::Grammar::Spec.new(
            namespace:       ns,
            name:            cmd,
            aliases:         [],
            slots:           [],
            description_key: desc_key,
            auth:            :any
          )
        else
          nil
        end
      end

      # Reset DSL ivars — called from each base class's `inherited` hook.
      def reset_grammar_ivars!
        instance_variable_set(:@_grammar_slots,           nil)
        instance_variable_set(:@_grammar_aliases,         nil)
        instance_variable_set(:@_grammar_auth,            nil)
        instance_variable_set(:@_grammar_description_key, nil)
        instance_variable_set(:@_grammar_declared,        false)
      end

      private

      # Derive the grammar namespace symbol from the class's module ancestry.
      def _grammar_namespace
        parent = module_parent_name || name&.split("::")&.first(2)&.last
        case parent
        when "Slash"    then :slash
        when "Chat"     then :chat
        when "Hashtag"  then :hashtag
        else
          # Fallback: scan ancestors
          if ancestors.any? { |a| a.name&.start_with?("Pito::Slash") }
            :slash
          elsif ancestors.any? { |a| a.name&.start_with?("Pito::Chat") }
            :chat
          elsif ancestors.any? { |a| a.name&.start_with?("Pito::Hashtag") }
            :hashtag
          end
        end
      end

      # Retrieve the canonical command name symbol.
      # Slash and Chat use `tool`; Hashtag uses `handle`.
      def _grammar_command_name
        ns = _grammar_namespace
        method_name =
          case ns
          when :hashtag then :handle
          else               :tool
          end
        return nil unless respond_to?(method_name)

        begin
          value = public_send(method_name)
          value&.to_sym
        rescue NotImplementedError
          nil
        end
      end
    end
  end
end
