# frozen_string_literal: true

require "set"

module Pito
  module Grammar
    # Thin module that bridges the old constant-based vocabulary API to the
    # new config-driven source (Pito::Grammar::ConfigSource, T8.8 migration).
    #
    # The static Vocabulary.define(…) constants that once lived here (NOUNS,
    # GENRES, PLATFORMS, METRICS, etc.) have been deleted — they are now built
    # from config/pito/verbs.yml by ConfigSource. MASKED_CONFIG_KEYS and
    # PROVIDER_KEYS are non-vocabulary config helpers and remain here.
    #
    # External callers that referenced individual vocabulary objects by constant
    # (e.g. Vocabularies::GAME_TITLES, Vocabularies::VISIT_DESTINATIONS) must
    # use Pito::Grammar::Registry.vocabulary(:name) instead, which is populated
    # at boot by Vocabularies.register_all! → ConfigSource.vocabularies.
    module Vocabularies
      # Config keys whose values are considered secret and should be masked in UI.
      MASKED_CONFIG_KEYS = Set["client_id", "client_secret", "api_key"].freeze

      # Per-provider kv key lists — single source of truth for autocomplete.
      # These mirror the keys in Pito::Slash::Handlers::Config::PROVIDER_SETTERS.
      PROVIDER_KEYS = {
        "google"   => %w[client_id client_secret redirect_uri api_key],
        "voyage"   => %w[api_key],
        "igdb"     => %w[client_id client_secret],
        "webhook"  => %w[slack discord],
        "me"       => %w[nickname],
        "sound"    => [],
        "timezone" => []
      }.freeze

      # Returns the allowed kv keys for +provider+ (downcased string).
      # Returns [] for unknown providers.
      def self.provider_keys(provider)
        PROVIDER_KEYS.fetch(provider.to_s.downcase, [])
      end

      # ── Public API ───────────────────────────────────────────────────────────

      # Returns all Vocabulary objects, built from config/pito/verbs.yml via
      # Pito::Grammar::ConfigSource. Replaces the former hand-authored constant array.
      def self.all
        Pito::Grammar::ConfigSource.vocabularies
      end

      def self.register_all!(registry)
        all.each { |vocab| registry.register_vocabulary(vocab) }
      end
    end
  end
end
