# frozen_string_literal: true

require "set"

module Pito
  module Grammar
    module Vocabularies
      # Config keys whose values are considered secret and should be masked in UI.
      MASKED_CONFIG_KEYS = Set["client_id", "client_secret", "api_key"].freeze

      # ── Static vocabularies ──────────────────────────────────────────────────

      SLASH_VERBS = Vocabulary.define(
        name:      :slash_verbs,
        canonical: %w[config disconnect help themes]
      ).freeze

      CONFIG_PROVIDERS = Vocabulary.define(
        name:      :config_providers,
        canonical: %w[google voyage igdb webhook sound fx]
      ).freeze

      CONFIG_KEYS = Vocabulary.define(
        name:      :config_keys,
        canonical: %w[client_id client_secret redirect_uri api_key slack discord]
      ).freeze

      GENRES = Vocabulary.define(
        name:      :genres,
        canonical: [ "Shooter", "Simulation", "RPG", "Racing", "Strategy",
                    "Sports", "Puzzle", "Platformer", "Fighting", "Adventure" ],
        synonyms:  {
          "fps"        => "Shooter",
          "shooter"    => "Shooter",
          "sim"        => "Simulation",
          "simulation" => "Simulation",
          "rpg"        => "RPG",
          "racing"     => "Racing",
          "strategy"   => "Strategy",
          "sports"     => "Sports",
          "puzzle"     => "Puzzle",
          "platformer" => "Platformer",
          "fighting"   => "Fighting",
          "adventure"  => "Adventure"
        }
      ).freeze

      PLATFORMS = Vocabulary.define(
        name:      :platforms,
        canonical: [ "PlayStation 5", "Nintendo Switch", "PC", "Xbox Series X",
                    "PlayStation 4", "Xbox One", "iOS", "Android" ],
        synonyms:  {
          "ps5"         => "PlayStation 5",
          "playstation" => "PlayStation 5",
          "ps"          => "PlayStation 5",
          "sony"        => "PlayStation 5",
          "switch"      => "Nintendo Switch",
          "steam"       => "PC",
          "pc"          => "PC",
          "xbox"        => "Xbox Series X"
        }
      ).freeze

      RELEASE_STATUS = Vocabulary.define(
        name:      :release_status,
        canonical: %w[released upcoming tba],
        synonyms:  {
          "unreleased"        => "upcoming",
          "to be announced"   => "tba",
          "tbd"               => "tba"
        }
      ).freeze

      METRICS = Vocabulary.define(
        name:      :metrics,
        canonical: [ "subscribers", "views", "ctr", "watch time" ],
        synonyms:  {
          "subs"          => "subscribers",
          "watched hours" => "watch time",
          "hours"         => "watch time"
        },
        fillers:   %w[count ratio]
      ).freeze

      ON_OFF = Vocabulary.define(
        name:      :on_off,
        canonical: %w[on off],
        synonyms:  {
          "true"     => "on",
          "false"    => "off",
          "enable"   => "on",
          "disable"  => "off",
          "yes"      => "on",
          "no"       => "off",
          "enabled"  => "on",
          "disabled" => "off"
        }
      ).freeze

      HASHTAG_VERBS = Vocabulary.define(
        name:      :hashtag_verbs,
        canonical: %w[add remove],
        synonyms:  {
          "drop"    => "remove",
          "delete"  => "remove",
          "include" => "add"
        }
      ).freeze

      FILLERS = Vocabulary.define(
        name:      :fillers,
        canonical: [],
        fillers:   %w[the a an games game please by ordered sorted show me]
      ).freeze

      CONNECTIVES = Vocabulary.define(
        name:      :connectives,
        canonical: %w[and for]
      ).freeze

      # ── Theme vocabularies ───────────────────────────────────────────────────

      # Subcommand keywords for `/themes`, with vocabulary synonyms providing the
      # production-correct alias surface.
      #
      # WHY vocabulary synonyms (not Spec.aliases)?
      #   Spec.aliases operate at the *verb* level — they map one top-level slash
      #   verb name to another (e.g. `/cfg` → same Spec as `/config`).  The theme
      #   subcommands (`list`, `preview`, `apply`, `reset`) are *values* parsed from
      #   `invocation.args`, not separate verbs.  The Vocabulary synonym mechanism
      #   is exactly the right layer: the handler resolves `args.first` through this
      #   vocabulary, `"ls"` canonicalizes to `"list"`, and the dispatcher sees only
      #   canonical forms.  No verb-level alias is registered or needed.
      #
      # REUSABILITY
      #   Any future command with its own keyword subcommands and synonyms follows
      #   the same pattern: define a static Vocabulary with canonical names + a
      #   synonyms Hash, register it in `Vocabularies.all`, and call
      #   `vocab.resolve(arg)` in the handler before dispatching.  The grammar,
      #   registry, and autocomplete engine are unchanged.
      THEME_SUBCOMMANDS = Vocabulary.define(
        name:      :theme_subcommands,
        canonical: %w[list preview apply reset],
        synonyms:  {
          "ls" => "list"
        }
      ).freeze

      # All registered theme slugs plus the special alias "default" (→ tokyo-night).
      # Backed by the theme Registry so adding a new definition file automatically
      # extends the vocabulary on next boot — no manual wiring needed.
      THEME_NAMES = Vocabulary.define(
        name:      :theme_names,
        dynamic:   true,
        resolver:  ->(_context) { Pito::Themes::Registry.names + [ "default" ] }
      ).freeze

      # ── Dynamic vocabulary stubs ─────────────────────────────────────────────

      CHANNELS = Vocabulary.define(
        name:     :channels,
        dynamic:  true,
        resolver: ->(context) { Channel.pluck(:handle) }
      ).freeze

      CONVERSATIONS = Vocabulary.define(
        name:     :conversations,
        dynamic:  true,
        resolver: ->(context) { Conversation.order(updated_at: :desc).limit(50).pluck(:uuid) }
      ).freeze

      GAME_TITLES = Vocabulary.define(
        name:     :game_titles,
        dynamic:  true,
        resolver: ->(context) { ::Game.where("title ILIKE ?", "#{context}%").limit(20).pluck(:title) }
      ).freeze

      # Per-provider kv key lists — single source of truth for autocomplete.
      # These mirror the keys in Pito::Slash::Handlers::Config::PROVIDER_SETTERS.
      PROVIDER_KEYS = {
        "google"  => %w[client_id client_secret redirect_uri api_key],
        "voyage"  => %w[api_key],
        "igdb"    => %w[client_id client_secret],
        "webhook" => %w[slack discord],
        "sound"   => [],
        "fx"      => []
      }.freeze

      # Returns the allowed kv keys for +provider+ (downcased string).
      # Returns [] for unknown providers.
      def self.provider_keys(provider)
        PROVIDER_KEYS.fetch(provider.to_s.downcase, [])
      end

      # ── Public API ───────────────────────────────────────────────────────────

      def self.all
        [
          SLASH_VERBS,
          CONFIG_PROVIDERS,
          CONFIG_KEYS,
          ON_OFF,
          GENRES,
          PLATFORMS,
          RELEASE_STATUS,
          METRICS,
          HASHTAG_VERBS,
          FILLERS,
          CONNECTIVES,
          CHANNELS,
          CONVERSATIONS,
          GAME_TITLES,
          THEME_SUBCOMMANDS,
          THEME_NAMES
        ]
      end

      def self.register_all!(registry)
        all.each { |vocab| registry.register_vocabulary(vocab) }
      end
    end
  end
end
