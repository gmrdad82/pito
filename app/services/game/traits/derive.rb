# frozen_string_literal: true

class Game
  module Traits
    # Deterministic IGDB-data -> trait mapping (traits-design.md section 5).
    # Computes every tag declared `source: derived` in config/pito/traits.yml
    # from columns/associations pito already syncs, then delegates the write
    # to Game::Traits::Apply with `source: "derived"` — so owner pins are
    # never touched (Apply's owner guard) and the row is validated the same
    # way every other writer is.
    #
    # Idempotent + self-healing: re-running recomputes the full derived set
    # from current facts every time — `add_tags` is what SHOULD be true now,
    # `remove_tags` is every currently-derived-sourced tag that no longer
    # computes true (so a stale derived tag heals after an IGDB re-sync
    # changes the underlying facts; an owner-pinned tag is untouched because
    # it never carries `source: "derived"` on the row).
    module Derive
      # trait name => 1-arg lambda(game) => Boolean. Mirrors the mapping
      # table in traits-design.md section 5 exactly; every rule reads
      # columns/associations already verified present on Game/GameMapper.
      RULES = {
        "platformer" => ->(game) { genre_name?(game, "Platform") },
        "simulation" => ->(game) { genre_name?(game, "Simulator") },
        "guns" => ->(game) { genre_name?(game, "Shooter") },
        "action" => ->(game) { theme?(game, "Action") },
        "horror" => ->(game) { theme?(game, "Horror") },
        "survival" => ->(game) { theme?(game, "Survival") },
        "war" => ->(game) { theme?(game, "Warfare") },
        "time_consuming" => lambda { |game|
          game.ttb_main_seconds.to_i >= 144_000 || game.ttb_completionist_seconds.to_i >= 288_000
        },
        "acclaimed" => lambda { |game|
          (game.aggregated_rating.to_f >= 85 && game.aggregated_rating_count.to_i >= 5) ||
            (game.total_rating.to_f >= 85 && game.total_rating_count.to_i >= 100)
        },
        # ── L6 flip (2026-07-17): game_modes / hypes / age_ratings synced ──
        "multiplayer" => ->(game) { game_mode?(game, "Multiplayer") || game_mode?(game, "Co-operative") },
        "single_player" => ->(game) { game_mode?(game, "Single player") },
        "hyped" => ->(game) { game.hypes.to_i >= HYPED_FOLLOWS_THRESHOLD },
        "family_friendly" => ->(game) { family_friendly_rating?(game) },
        # ── Q32 wishlist (2026-07-20): genre/theme facts already synced —
        #    names verified against synced data (sync_game_spec fixtures);
        #    "racing" deliberately collapses the owner's "racing" + "driving"
        #    into one genre-mapped tag (traits.yml ledger). ──────────────────
        "adventure" => ->(game) { genre_name?(game, "Adventure") },
        "role_playing" => ->(game) { genre_name?(game, "Role-playing (RPG)") },
        "racing" => ->(game) { genre_name?(game, "Racing") },
        "open_world" => ->(game) { theme?(game, "Open world") }
      }.freeze

      # `hypes` is IGDB's pre-release follow count. Threshold picked
      # empirically 2026-07-17 against LIVE IGDB data (not guessed):
      # already-released ordinary titles sit in single digits (Stardew
      # Valley 1, GTA VI: Ultimate Edition 4, Mafia: The Old Country - Man
      # of Honor 7) while genuinely buzzy titles clear 50+ (Elden Ring
      # Nightreign 65, Elden Ring 96, Death Stranding 2: On the Beach 188,
      # Hollow Knight: Silksong 220, Mafia: The Old Country 238, Grand
      # Theft Auto VI 959). TUNABLE — revisit once real synced rows carry
      # a wider distribution.
      HYPED_FOLLOWS_THRESHOLD = 50

      # ESRB / PEGI ratings that read as "safe for the kids" (owner spec:
      # "ESRB E/E10+ or PEGI 3/7"). String values verified LIVE against
      # IGDB v4 2026-07-17 — see Game::Igdb::Client::GAME_FIELDS for the
      # query shape and the exact confirmed values ("E", "E10+", "3",
      # "7", queried against Animal Crossing: New Horizons, Mario Kart 8
      # Deluxe, Splatoon 3, Kirby and the Forgotten Land). TUNABLE — the
      # owner may want ESRB "EC" (early childhood) or PEGI "12" folded in
      # later; both intentionally excluded for now per the exact spec.
      FAMILY_FRIENDLY_ESRB_RATINGS = %w[E E10+].freeze
      FAMILY_FRIENDLY_PEGI_RATINGS = %w[3 7].freeze

      module_function

      # @param game [Game]
      # @return [Hash] Apply's result unchanged: { changed:, skipped_owner: }
      def call(game)
        computed = RULES.select { |_name, rule| rule.call(game) }.keys
        stale = currently_derived_tags(game) - computed

        Game::Traits::Apply.call(game: game, source: "derived", add_tags: computed, remove_tags: stale)
      end

      # Declared derived tags currently sourced "derived" on this game —
      # everything Derive itself last set, excluding any tag an owner has
      # since pinned (a pin's sources entry reads "owner", not "derived").
      def currently_derived_tags(game)
        Game::Traits::Vocabulary.derived_tag_names.select { |name| game.trait_source(name) == "derived" }
      end

      def genre_name?(game, name)
        game.genres.any? { |genre| genre.name.to_s.casecmp?(name) }
      end

      def theme?(game, name)
        Array(game.themes).any? { |theme| theme.to_s.casecmp?(name) }
      end

      def game_mode?(game, name)
        Array(game.game_modes).any? { |mode| mode.to_s.casecmp?(name) }
      end

      def family_friendly_rating?(game)
        ratings = game.age_ratings || {}
        FAMILY_FRIENDLY_ESRB_RATINGS.any? { |r| r.casecmp?(ratings["ESRB"].to_s) } ||
          FAMILY_FRIENDLY_PEGI_RATINGS.any? { |r| r.casecmp?(ratings["PEGI"].to_s) }
      end
    end
  end
end
