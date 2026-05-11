# Phase 27 §1a — relax + backfill the `platforms` table so it can host
# manually-seeded rows (PS5, Switch 2, Steam, GOG, Epic) and serve as
# the canonical reference table the per-platform-ownership join points
# at.
#
# Two shape changes:
#
#   1. `igdb_id` becomes NULLable. Phase 14 §1 created the column as
#      `NOT NULL` because every row was lazily upserted from IGDB. Seeded
#      rows pre-exist before any IGDB sync, so the column must accept
#      `NULL` for the seed step to land. A subsequent IGDB sync fills
#      the column on first match. The existing unique index already
#      permits multiple NULLs (Postgres behavior) — left untouched.
#
#   2. `slug` gains a backfill + becomes `NOT NULL` + uniquely indexed.
#      Phase 27 introduces FriendlyId on Platform with the `slugged`
#      module; the model needs a NOT-NULL unique slug column it can
#      route to.
#
# The backfill derives slugs from `name` for every existing row that
# has a blank slug. The mapping uses `Pito::SlugBuilder` (the same
# helper Collection / Project / Bundle / MilestoneRule use) so the
# generated slugs match the project's slug shape convention.
class RevampPlatformsForFriendlyId < ActiveRecord::Migration[8.1]
  def up
    change_column_null :platforms, :igdb_id, true

    # Backfill blank slugs from name. Idempotent — rows that already
    # carry a slug are left alone.
    execute(<<~SQL)
      UPDATE platforms
      SET slug = lower(regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g'))
      WHERE slug IS NULL OR slug = '';
    SQL

    # Strip leading/trailing dashes the cheap regex above might have
    # left in place (e.g. "Steam" → "steam"; "PlayStation 5" →
    # "playstation-5"; "Xbox 360 " → "xbox-360-" → "xbox-360").
    execute(<<~SQL)
      UPDATE platforms
      SET slug = regexp_replace(slug, '^-+|-+$', '', 'g');
    SQL

    change_column_null :platforms, :slug, false
    add_index :platforms, :slug, unique: true
  end

  def down
    remove_index :platforms, :slug
    change_column_null :platforms, :slug, true
    change_column_null :platforms, :igdb_id, false
  end
end
