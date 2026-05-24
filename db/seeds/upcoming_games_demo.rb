# Demo seed — populates the home-screen "upcoming games" panel with
# 6-10 owned games whose `release_date` lands inside the
# [today + 3, today + 28] window. Idempotent: re-running this file is
# a no-op except for re-shifting release dates of the demo rows when
# they slip out of the upcoming window (so the seed survives a clock
# advancing past the originally-seeded dates).
#
# Strategy:
#
#   1. Pick from a curated list of high-recognition titles (real
#      upcoming + recent releases). For each entry, `find_or_create_by`
#      a Game keyed on its IGDB-style slug — when the row already
#      exists (from a prior IGDB sync or from a previous seed run),
#      reuse it; otherwise insert a minimal record.
#
#   2. Force `release_date` into a deterministic-per-title offset of
#      `today + N.days` (N varies per title to spread the shelf out).
#      A re-seed weeks later re-shifts the dates so the demo stays
#      "alive" without manual maintenance.
#
#   3. Ensure each game has at least one `GamePlatformOwnership` row
#      pointing at one of the canonical Platform rows (PS5 / Switch 2 /
#      Steam) so it qualifies for `Game.owned`. `find_or_create_by!`
#      is idempotent against the platform_id uniqueness scope on the
#      join.
#
# Hook from `db/seeds.rb` via `load Rails.root.join("db/seeds/upcoming_games_demo.rb")`.
# Standalone runs (`bin/rails runner 'load …'`) also supported.
#
# Skipped in production — this is dev / demo data only.

if Rails.env.production?
  warn "  upcoming-games demo seed skipped (production env)."
else
  puts "seeding upcoming-games demo (owned games with release_date in the next 30d)..."

  # Curated demo list. Each entry:
  #   slug:             FriendlyId / IGDB-style slug (stable lookup key)
  #   title:            display title
  #   days_out:         offset from today for the seeded release_date
  #                     (must be in [3, 28] so it lands inside the panel's
  #                     upcoming window)
  #   platforms:        array of canonical Platform names this row is
  #                     "owned on" (one ownership row per entry; first
  #                     name wins as the primary chip)
  #   cover_image_id:   optional pre-known IGDB image id so the cover
  #                     renders even on a fresh DB without an IGDB sync
  upcoming_demo_titles = [
    { slug: "gta-vi",                title: "Grand Theft Auto VI",        days_out:  5, platforms: [ "PlayStation 5" ], cover_image_id: "co1qda" },
    { slug: "hollow-knight-silksong", title: "Hollow Knight: Silksong",   days_out:  8, platforms: [ "Steam", "Nintendo Switch 2" ], cover_image_id: "co2bgz" },
    { slug: "metroid-prime-4-beyond", title: "Metroid Prime 4: Beyond",   days_out: 12, platforms: [ "Nintendo Switch 2" ], cover_image_id: "co8tnf" },
    { slug: "fable",                 title: "Fable",                      days_out: 15, platforms: [ "Steam" ], cover_image_id: "co7ds6" },
    { slug: "death-stranding-2",     title: "Death Stranding 2: On the Beach", days_out: 18, platforms: [ "PlayStation 5" ], cover_image_id: "co9d2k" },
    { slug: "monster-hunter-wilds",  title: "Monster Hunter Wilds",       days_out: 22, platforms: [ "PlayStation 5", "Steam" ], cover_image_id: "co8wd7" },
    { slug: "elden-ring-nightreign", title: "Elden Ring Nightreign",      days_out: 25, platforms: [ "Steam", "PlayStation 5" ], cover_image_id: "co8jr0" },
    { slug: "marvels-wolverine",     title: "Marvel's Wolverine",         days_out: 28, platforms: [ "PlayStation 5" ], cover_image_id: "co8b2x" }
  ].freeze

  # Pre-resolve platform IDs once. `Platform.unscoped` because the
  # default scope on Platform (if any) does not include legacy /
  # backfilled rows; the upstream seed block uses `.unscoped` for the
  # same reason.
  platform_id_by_name = upcoming_demo_titles
    .flat_map { |t| t[:platforms] }
    .uniq
    .each_with_object({}) do |name, h|
      record = Platform.unscoped.find_by(name: name)
      h[name] = record.id if record
    end

  missing_platforms = upcoming_demo_titles
    .flat_map { |t| t[:platforms] }
    .uniq
    .reject { |n| platform_id_by_name.key?(n) }

  if missing_platforms.any?
    warn "  WARNING: missing platforms — skipping demo titles that need #{missing_platforms.inspect}."
    warn "           run the main `seeds.rb` first so the canonical Platform rows exist."
  end

  upserts = 0
  skipped = 0
  upcoming_demo_titles.each do |entry|
    # Drop any entry whose platforms are entirely missing — they can't
    # be marked owned without a Platform row to bind against.
    resolved_platform_ids = entry[:platforms].map { |n| platform_id_by_name[n] }.compact
    if resolved_platform_ids.empty?
      skipped += 1
      next
    end

    target_release_date = Date.current + entry[:days_out].days

    game = Game.find_or_initialize_by(igdb_slug: entry[:slug])
    game.title          = entry[:title]
    game.release_date   = target_release_date
    # `release_year` keeps in sync with `release_date` so any
    # downstream surface filtering by year (the IGDB-sync code uses
    # this) stays consistent with the demo override.
    game.release_year   = target_release_date.year
    # Only stamp `cover_image_id` when the row is brand new OR when it
    # is still blank — never clobber a real IGDB-synced cover id on
    # an existing row.
    game.cover_image_id ||= entry[:cover_image_id]
    # `release_precision` "day" so any calendar / formatter code that
    # branches on precision treats the date as fully resolved.
    game.release_precision = "day" if game.respond_to?(:release_precision=)

    game.save!
    upserts += 1

    # Ensure ownership rows. `find_or_create_by!` is idempotent against
    # the per-(game, platform) uniqueness; re-running this seed leaves
    # the join row untouched.
    resolved_platform_ids.each do |platform_id|
      GamePlatformOwnership.find_or_create_by!(game_id: game.id, platform_id: platform_id)
    end
  end

  puts "  upserts: #{upserts} (skipped #{skipped} for missing platforms)"
  puts "  Game.owned.where(release_date: today..today+30d).count = " \
       "#{Game.owned.where(release_date: Date.current..(Date.current + 30.days)).count}"
end
