# Phase 28 §01a — Multi-version game grouping. One-shot rake task to
# backfill `games.version_parent_id` for existing rows whose titles
# match common edition suffixes ("Deluxe", "Standard", "Game of the
# Year", "GOTY", "Collector's", "Definitive", "Anniversary",
# "Ultimate"). Idempotent — safe to re-run.
#
# Behaviour (locked per spec §"Backfill rake task"):
#
#   - Walk every primary `Game` row (`version_parent_id IS NULL`).
#   - Strip the suffix to compute a base title; case-insensitive,
#     anchored to end of title.
#   - If a stripped base matches another existing PRIMARY's title
#     (case-insensitive, exact match), attach the row as an edition
#     of that primary, stamping `version_title` with the captured
#     suffix (normalised).
#   - If no match exists, leave the row alone (no synthetic parent).
#   - Print a summary `attached: N, skipped: M, total: T`.
#
# Edge cases the task does NOT handle (architect lean #6 locked
# "wait"):
#   - Parenthesised variants ("Game (Deluxe Edition)").
#   - Multi-sub-game collections ("Halo: The Master Chief Collection").
namespace :pito do
  desc "Backfill games.version_parent_id by regex on existing titles. Idempotent."
  task backfill_version_parents: :environment do
    # `[suffix_regex, normalised_label]`. Order matters: longer
    # suffixes win first so " Deluxe Edition" matches before " Deluxe".
    suffixes = [
      [ /\s+game of the year edition\z/i, "Game of the Year" ],
      [ /\s+game of the year\z/i,         "Game of the Year" ],
      [ /\s+goty edition\z/i,             "Game of the Year" ],
      [ /\s+goty\z/i,                     "Game of the Year" ],
      [ /\s+collector'?s edition\z/i,     "Collector's" ],
      [ /\s+collector edition\z/i,        "Collector's" ],
      [ /\s+definitive edition\z/i,       "Definitive" ],
      [ /\s+anniversary edition\z/i,      "Anniversary" ],
      [ /\s+ultimate edition\z/i,         "Ultimate" ],
      [ /\s+deluxe edition\z/i,           "Deluxe" ],
      [ /\s+deluxe\z/i,                   "Deluxe" ],
      [ /\s+standard edition\z/i,         "Standard" ],
      [ /\s+standard\z/i,                 "Standard" ]
    ]

    attached = 0
    skipped  = 0
    total    = 0

    Game.where(version_parent_id: nil).find_each do |game|
      total += 1
      title  = game.title.to_s
      label  = nil
      base   = nil

      suffixes.each do |regex, normalised|
        match = title.match(regex)
        next unless match

        label = normalised
        base  = title.sub(regex, "").strip
        break
      end

      if label.nil? || base.blank? || base.casecmp(title).zero?
        skipped += 1
        next
      end

      parent = Game.primaries
                   .where("LOWER(title) = ?", base.downcase)
                   .where.not(id: game.id)
                   .first

      if parent.nil?
        skipped += 1
        next
      end

      # `update_columns` to bypass callbacks + validators (the parent
      # is guaranteed primary by the `.primaries` scope above; we
      # skip the model-level guards to keep the write a single,
      # auditable UPDATE per row).
      game.update_columns(version_parent_id: parent.id, version_title: label)
      attached += 1
    end

    puts "attached: #{attached}, skipped: #{skipped}, total: #{total}."
  end
end
