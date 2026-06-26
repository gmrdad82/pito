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
        canonical: %w[google voyage igdb webhook me sound motion fx timezone]
      ).freeze

      CONFIG_KEYS = Vocabulary.define(
        name:      :config_keys,
        canonical: %w[client_id client_secret redirect_uri api_key slack discord nickname]
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
        canonical: [ "subs", "views", "ctr", "watch time" ],
        synonyms:  {
          "subscriber"    => "subs",
          "subscribers"   => "subs",
          "watched hours" => "watch time",
          "hours"         => "watch time"
        },
        fillers:   %w[count ratio]
      ).freeze

      # Reveal effects for the `/config fx <effect>` enum provider. Canonical
      # values mirror AppSetting::FX_EFFECTS — the suggestions engine ghosts these
      # after `/config fx `.
      FX_EFFECTS = Vocabulary.define(
        name:      :fx_effects,
        canonical: %w[typewriter scramble comet]
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

      # Listable entity nouns for the `list`/`ls` verb. Order matters — this is
      # the suggestion order shown after `list `. (videos not listable yet, but
      # offered so the noun is recognised and the ghost is honest.)
      NOUNS = Vocabulary.define(
        name:      :nouns,
        canonical: %w[channels vids games],
        synonyms:  {
          "channel" => "channels",
          "video"   => "vids",
          "videos"  => "vids",
          "vid"     => "vids",
          "game"    => "games",
          "gamez"   => "games"
        }
      ).freeze

      HASHTAG_VERBS = Vocabulary.define(
        name:      :hashtag_verbs,
        canonical: %w[with without],
        synonyms:  {
          "drop"    => "without",
          "delete"  => "without",
          "include" => "with"
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

      # Subcommand keywords for `/games`.
      GAMES_SUBCOMMANDS = Vocabulary.define(
        name:      :games_subcommands,
        canonical: %w[import]
      ).freeze

      # Subcommand keywords for `/jobs` (drives palette / ghost suggestions:
      # `/jobs ` offers these, like `/config fx` offers the effects).
      JOBS_SUBCOMMANDS = Vocabulary.define(
        name:      :jobs_subcommands,
        canonical: %w[status requeue run pause resume]
      ).freeze

      # Noun for the `import` chat verb (drives ghost completion: `import ` → `game`).
      # Only `game` is suggested — `import videos` is a de-emphasized alias of
      # `sync videos` and is NOT offered as a primary suggestion. Typed
      # `import videos` still routes via the handler's raw-text match.
      IMPORT_NOUNS = Vocabulary.define(
        name:      :import_nouns,
        canonical: %w[game],
        synonyms:  { "games" => "game" }
      ).freeze

      # Targets for the `sync` chat verb (drives ghost completion: `sync ` →
      # `channels`/`videos`). Mirrors what Pito::Chat::Handlers::Sync routes on.
      SYNC_TARGETS = Vocabulary.define(
        name:      :sync_targets,
        canonical: %w[channels vids],
        synonyms:  {
          "channel" => "channels",
          "video"   => "vids",
          "videos"  => "vids",
          "vid"     => "vids"
        }
      ).freeze

      # Keyword option for the `<when>` slot of the `schedule` verb. `slate` is
      # the next-open-slot alternative to an explicit date/time — surfaced so the
      # suggestions engine can ghost it after `schedule …` (chat) and
      # `#<handle> schedule …` (reply). Mirrors Schedule#SLATE_KEYWORD.
      SCHEDULE_WHENS = Vocabulary.define(
        name:      :schedule_whens,
        canonical: %w[slate]
      ).freeze

      # Subcommands of the `price` verb (`price set <id> <amount>` /
      # `price unset <id>`) — surfaced so the suggestions engine ghosts `set`/`unset`
      # after `price ` (chat) and `#<handle> price ` (reply). Mirrors
      # Pito::MessageBuilder::CommandHelp::VERB_NOUNS[:price].
      PRICE_SUBCOMMANDS = Vocabulary.define(
        name:      :price_subcommands,
        canonical: %w[set unset]
      ).freeze

      # Subcommands of the `platform` verb (`platform set <id> <name>` /
      # `platform unset <id> <name>`) — surfaced so the suggestions engine ghosts
      # `set`/`unset` after `platform ` (chat) and `#<handle> platform ` (reply).
      PLATFORM_SUBCOMMANDS = Vocabulary.define(
        name:      :platform_subcommands,
        canonical: %w[set unset]
      ).freeze

      # ── Dynamic vocabulary stubs ─────────────────────────────────────────────

      CHANNELS = Vocabulary.define(
        name:     :channels,
        dynamic:  true,
        resolver: ->(context) { ::Channel.pluck(:handle) }
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

      VIDEO_TITLES = Vocabulary.define(
        name:     :video_titles,
        dynamic:  true,
        resolver: ->(context) { ::Video.where("title ILIKE ?", "#{context}%").limit(20).pluck(:title) }
      ).freeze

      # Per-provider kv key lists — single source of truth for autocomplete.
      # These mirror the keys in Pito::Slash::Handlers::Config::PROVIDER_SETTERS.
      PROVIDER_KEYS = {
        "google"   => %w[client_id client_secret redirect_uri api_key],
        "voyage"   => %w[api_key],
        "igdb"     => %w[client_id client_secret],
        "webhook"  => %w[slack discord],
        "me"       => %w[nickname],
        "sound"    => [],
        "motion"   => [],
        "fx"       => [],
        "timezone" => []
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
          FX_EFFECTS,
          ON_OFF,
          GENRES,
          PLATFORMS,
          RELEASE_STATUS,
          METRICS,
          NOUNS,
          HASHTAG_VERBS,
          FILLERS,
          CONNECTIVES,
          CHANNELS,
          CONVERSATIONS,
          GAME_TITLES,
          VIDEO_TITLES,
          GAMES_SUBCOMMANDS,
          JOBS_SUBCOMMANDS,
          IMPORT_NOUNS,
          SYNC_TARGETS,
          SCHEDULE_WHENS,
          PRICE_SUBCOMMANDS,
          PLATFORM_SUBCOMMANDS
        ]
      end

      def self.register_all!(registry)
        all.each { |vocab| registry.register_vocabulary(vocab) }
      end
    end
  end
end
