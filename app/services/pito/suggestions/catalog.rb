# frozen_string_literal: true

module Pito
  module Suggestions
    # Builds the static suggestions catalog embedded in the page.
    #
    # The catalog lets the client filter slash/hashtag/chat completions offline
    # without a round-trip. Dynamic (DB-backed) vocabularies are NOT embedded —
    # they appear as endpoint pointers only.
    #
    # Usage:
    #   Pito::Suggestions::Catalog.to_h(authenticated: true)
    #   Pito::Suggestions::Catalog.to_json(authenticated: false)
    module Catalog
      DYNAMIC_ENDPOINT = "/suggestions"

      class << self
        # Returns the full catalog Hash.
        #
        # authenticated: Boolean
        #   false → slash section contains ONLY :unauthenticated_only specs (login)
        #   true  → slash section contains all specs EXCEPT :unauthenticated_only (login)
        def to_h(authenticated:)
          {
            slash:        slash_entries(authenticated:),
            hashtag:      namespace_entries(:hashtag),
            chat:         namespace_entries(:chat),
            vocabularies: vocabulary_entries
          }
        end

        # Returns to_h serialized as JSON.
        def to_json(authenticated:)
          to_h(authenticated:).to_json
        end

        private

        # ── Slash ────────────────────────────────────────────────────────────

        # Auth-filter rule:
        #   unauthenticated (authenticated: false) → keep ONLY :unauthenticated_only specs
        #   authenticated   (authenticated: true)  → keep all EXCEPT :unauthenticated_only specs
        def slash_entries(authenticated:)
          Pito::Grammar::Registry.specs(namespace: :slash)
                  .select { |spec| include_slash_spec?(spec, authenticated:) }
                  .map    { |spec| spec_to_slash_entry(spec) }
        end

        def include_slash_spec?(spec, authenticated:)
          if authenticated
            spec.auth != :unauthenticated_only
          else
            spec.auth == :unauthenticated_only
          end
        end

        def spec_to_slash_entry(spec)
          {
            name:        spec.name.to_s,
            insert:      "/#{spec.name} ",
            description: description_for(spec),
            auth:        spec.auth
          }
        end

        # ── Hashtag / Chat ───────────────────────────────────────────────────

        # Hashtag: insert is the bare verb token (no leading #, because the
        # #handle token precedes the verb in the actual input stream).
        # Chat:    insert is the bare verb token as well.
        def namespace_entries(namespace)
          Pito::Grammar::Registry.specs(namespace:)
                  .map { |spec| spec_to_entry(spec) }
        end

        def spec_to_entry(spec)
          {
            name:        spec.name.to_s,
            insert:      "#{spec.name} ",
            description: description_for(spec),
            slots:       slots_for(spec)
          }
        end

        # Emit enum slots for a chat spec so the client ghost-logic can be
        # verb-aware without a hardcoded verb→slot mapping on the JS side.
        # Only :enum slots with a :source are included (free/kv/connective slots
        # carry no completion info the client can use).
        def slots_for(spec)
          spec.slots
              .select { |s| s.kind == :enum && s.source.is_a?(Symbol) }
              .map { |s| { name: s.name.to_s, source: s.source.to_s } }
        end

        # ── Vocabularies ─────────────────────────────────────────────────────

        def vocabulary_entries
          Pito::Grammar::Registry.vocabularies.each_with_object({}) do |vocab, hash|
            hash[vocab.name] = build_vocab_entry(vocab)
          end
        end

        def build_vocab_entry(vocab)
          if vocab.dynamic?
            { dynamic: true, endpoint: DYNAMIC_ENDPOINT }
          else
            entry = vocab.to_h.except(:name)
            if vocab.name == :config_keys
              entry[:masked_keys] = Pito::Grammar::Vocabularies::MASKED_CONFIG_KEYS.to_a.sort
            end
            entry
          end
        end

        # ── I18n helper ──────────────────────────────────────────────────────

        def description_for(spec)
          return "" if spec.description_key.nil?

          I18n.t(spec.description_key)
        end
      end
    end
  end
end
