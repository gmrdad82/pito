# frozen_string_literal: true

module Pito
  module Grammar
    # Builds Grammar Spec and Vocabulary objects from Pito::Dispatch::Config.data
    # (config/pito/verbs.yml). This is the config-driven source of truth for the
    # chat namespace and all vocabulary objects — replaces the hand-authored Ruby
    # tables in specs.rb (chat entries) and vocabularies.rb (static constants).
    #
    # CHAT SPEC MAPPING
    #   Every verb entry in verbs.yml that declares a `chat:` branch produces one
    #   Pito::Grammar::Spec with namespace :chat. Field mapping:
    #     name            → verb key (Symbol)
    #     aliases         → verb[:aliases] as Array<Symbol> (absent → [])
    #     slots           → chat[:slots] each converted by build_slot (see SLOT MAPPING)
    #     description_key → verb[:description] as String
    #     auth            → always :any (the verb-level YAML auth is a dispatch-routing
    #                       concept; Grammar Spec auth for chat is always :any, matching
    #                       the pre-migration hand-authored table behavior)
    #
    # SLASH SPEC MAPPING
    #   Every verb entry that declares a `slash:` branch produces one Spec with
    #   namespace :slash (replaces lib/pito/grammar/specs.rb and the
    #   per-handler `grammar do…end` blocks). Field mapping:
    #     name            → verb key (Symbol)
    #     aliases         → verb[:aliases] as Array<Symbol> (verb-level; the only
    #                       chat+slash verb, `help`, carries no aliases so this is
    #                       faithful for both branches)
    #     slots           → slash[:slots] each converted by build_slot
    #     description_key → slash[:description] as String (the BRANCH description —
    #                       distinct from verb[:description], which feeds the chat spec)
    #     auth            → slash[:auth].to_sym (:any | :unauthenticated_only |
    #                       :authenticated_only), the real palette auth gate; :any default
    #
    # SLOT MAPPING
    #   YAML slot fields → Pito::Grammar::Slot constructor args.
    #   Config loads the file with symbolize_names: true so all slot Hash keys are Symbols;
    #   values are their natural YAML types (String, Boolean, Array).
    #     name        → slot[:name].to_sym
    #     kind        → slot[:kind].to_sym   (:enum | :free | :literal | :kv)
    #     source      → slot[:source]&.to_sym   (nil for :free slots — free slots carry no source)
    #     optional    → slot[:optional] || false
    #     repeatable  → slot[:repeatable] || false
    #     introducer  → slot[:introducer]&.to_sym (nil when the key is absent)
    #     condition   → slot[:when] verbatim — a { prior_slot_name => [values] } Hash
    #                   already symbol-keyed by Config (nil when absent). Drives
    #                   Slot#eligible? for conditional slots (/config provider→keys).
    #
    # VOCABULARY MAPPING
    #   Static vocabs — those with a `members:` key (and optional `synonyms:`/`fillers:`):
    #     canonical  → members, each coerced to String
    #     synonyms   → synonyms Hash with String keys (YAML symbolizes hash keys; we
    #                  convert them back to strings so Vocabulary#resolve can look them up
    #                  by the String downcased form it always expects)
    #     fillers    → fillers Array, each coerced to String
    #   Dynamic vocabs — those with a `resolver:` key naming an entry in DYNAMIC_RESOLVERS:
    #     dynamic    → true
    #     resolver   → the lambda from DYNAMIC_RESOLVERS[resolver_name.to_sym]
    #
    # DYNAMIC_RESOLVERS
    #   Lambdas that query the DB cannot be expressed in YAML. The four dynamic
    #   vocabulary resolvers are registered here by name, exactly matching the
    #   `resolver:` keys used in verbs.yml's vocabularies section.
    module ConfigSource
      # Dynamic resolver lambdas, keyed by the resolver name declared in verbs.yml.
      # Each lambda accepts `context` (the current input prefix for completions) and
      # returns an Array<String>. DB references are intentional — these are runtime
      # adapters, not boot-time constants.
      DYNAMIC_RESOLVERS = {
        channels:      ->(context) { ::Channel.pluck(:handle) },
        conversations: ->(context) { ::Conversation.order(updated_at: :desc).limit(50).pluck(:uuid) },
        game_titles:   ->(context) { ::Game.where("title ILIKE ?", "#{context}%").limit(20).pluck(:title) },
        video_titles:  ->(context) { ::Video.where("title ILIKE ?", "#{context}%").limit(20).pluck(:title) }
      }.freeze

      module_function

      # Returns Array<Spec> for every verb in verbs.yml that declares a `chat:` branch.
      # Order mirrors the verbs.yml declaration order.
      def chat_specs
        Pito::Dispatch::Config.data.fetch(:verbs, {}).filter_map do |name, verb|
          next unless verb.is_a?(Hash) && verb.key?(:chat)

          Spec.new(
            namespace:       :chat,
            name:            name.to_sym,
            aliases:         Array(verb[:aliases]).map { |a| a.to_s.to_sym },
            slots:           build_slots(verb[:chat][:slots]),
            description_key: verb[:description]&.to_s,
            auth:            :any
          )
        end
      end

      # Returns Array<Spec> for every verb in verbs.yml that declares a `slash:`
      # branch. Order mirrors the verbs.yml declaration order. See SLASH SPEC MAPPING.
      def slash_specs
        Pito::Dispatch::Config.data.fetch(:verbs, {}).filter_map do |name, verb|
          next unless verb.is_a?(Hash) && verb.key?(:slash)

          slash = verb[:slash]
          Spec.new(
            namespace:       :slash,
            name:            name.to_sym,
            aliases:         Array(verb[:aliases]).map { |a| a.to_s.to_sym },
            slots:           build_slots(slash[:slots]),
            description_key: slash[:description]&.to_s,
            auth:            (slash[:auth] || "any").to_s.to_sym
          )
        end
      end

      # Returns Array<Vocabulary> for every entry in the `vocabularies:` section of
      # verbs.yml. Order mirrors the YAML declaration order.
      def vocabularies
        Pito::Dispatch::Config.data.fetch(:vocabularies, {}).map do |name, body|
          build_vocabulary(name, body)
        end
      end

      def build_slots(slots_data)
        Array(slots_data).map { |s| build_slot(s) }
      end

      def build_slot(s)
        Slot.new(
          name:        s[:name].to_sym,
          kind:        s[:kind].to_sym,
          source:      s[:source]&.to_sym,
          optional:    s.fetch(:optional, false),
          repeatable:  s.fetch(:repeatable, false),
          introducer:  s[:introducer]&.to_sym,
          condition:   s[:when]
        )
      end

      def build_vocabulary(name, body)
        if body.key?(:resolver)
          resolver_key = body[:resolver].to_s.to_sym
          lambda_fn    = DYNAMIC_RESOLVERS.fetch(resolver_key) do
            raise KeyError,
                  "Pito::Grammar::ConfigSource: no dynamic resolver registered for " \
                  "#{resolver_key.inspect}. Add it to DYNAMIC_RESOLVERS."
          end
          Vocabulary.define(
            name:     name.to_sym,
            dynamic:  true,
            resolver: lambda_fn
          )
        else
          Vocabulary.define(
            name:      name.to_sym,
            canonical: Array(body[:members]).map(&:to_s),
            synonyms:  (body[:synonyms] || {}).transform_keys(&:to_s),
            fillers:   Array(body[:fillers]).map(&:to_s)
          )
        end
      end
    end
  end
end
