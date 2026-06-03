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
        canonical: %w[config disconnect help]
      ).freeze

      CONFIG_PROVIDERS = Vocabulary.define(
        name:      :config_providers,
        canonical: %w[google voyage igdb webhook]
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
        resolver: ->(context) { Game.where("title ILIKE ?", "#{context}%").limit(20).pluck(:title) }
      ).freeze

      # ── Public API ───────────────────────────────────────────────────────────

      def self.all
        [
          SLASH_VERBS,
          CONFIG_PROVIDERS,
          CONFIG_KEYS,
          GENRES,
          PLATFORMS,
          RELEASE_STATUS,
          METRICS,
          HASHTAG_VERBS,
          FILLERS,
          CONNECTIVES,
          CHANNELS,
          CONVERSATIONS,
          GAME_TITLES
        ]
      end

      def self.register_all!(registry)
        all.each { |vocab| registry.register_vocabulary(vocab) }
      end
    end
  end
end
