# Phase 27 follow-up (2026-05-17) — Collection → Bundle consolidation.
#
# User direction: "bundle, collection, series — same thing. Call it bundle
# from now on." The `Collection` model is merged INTO `Bundle` as rows
# with `bundle_type: :collection`; the `games.collection_id` membership
# pointer is migrated to `bundle_members` rows; the `collections` table
# and the FK column are dropped.
#
# Data migration shape:
#
#   1. For each `collections` row, INSERT a `bundles` row with
#      `bundle_type: 1` (the `:collection` enum value), copying `name`,
#      `slug`, `composite_cover_path`, `composite_cover_checksum`.
#      Keep a mapping `old_collection_id → new_bundle_id` in a temp
#      table so step 2 can resolve memberships.
#   2. For each `games.collection_id IS NOT NULL` row, INSERT a
#      `bundle_members` row with `bundle_id = mapped_new_id`,
#      `game_id = games.id`, `position = next position in that bundle`
#      (alphabetical by game.title for stable ordering — the bundle's
#      composite cover composer will re-fingerprint independently of
#      position).
#   3. DROP the FK `games.collection_id → collections.id`, DROP the
#      `collection_id` column, DROP the `collections` table.
#
# Reversibility:
#
#   `down` recreates the `collections` table + the FK + the column,
#   then walks every `bundles` row with `bundle_type = 1` and:
#     a. INSERTs a corresponding `collections` row preserving id where
#        possible (we use a temp mapping in reverse so the join can
#        find it).
#     b. For each `bundle_members` row pointing at that bundle, writes
#        `games.collection_id = the recreated collection id`. A game
#        belonging to multiple collection-typed bundles (impossible in
#        the FORWARD direction because each game has exactly one
#        pre-migration collection, but possible in the reverse if the
#        user added the game to a second collection-typed bundle
#        post-migration) keeps the FIRST mapping; later ones are
#        dropped — the down path is a "best effort restore" not a
#        round-trip guarantee.
#     c. DROPs `bundle_members` rows for collection-typed bundles.
#     d. DROPs `bundles` rows with `bundle_type = 1`.
#
# Slug-collision safety: The forward step copies slugs from collections
# into bundles. If a collection slug collides with an existing bundle
# slug (rare — bundles slug from name via friendly_id and collections
# do the same, with the same slugger), we append `-c` and let
# friendly_id's later regen sort it out on the next save. The
# constraint here is the bundles.slug uniqueness index — a collision
# would crash the migration mid-flight. A 50-char cap on the appended
# slug stays inside the column's string size.
class MigrateCollectionsToBundles < ActiveRecord::Migration[8.1]
  # NOTE: NOT `disable_ddl_transaction!` — the temp tables created with
  # `ON COMMIT DROP` rely on the surrounding migration transaction so
  # they survive across the multi-step `execute` chain. Each
  # `execute` runs as its own statement in the shared transaction.

  COLLECTION_BUNDLE_TYPE = 1  # Bundle.bundle_types["collection"]

  def up
    # Bail cleanly if the collections table was already dropped (e.g.
    # by a previous failed run that got past step 3 then was reverted).
    return unless table_exists?(:collections)

    # Use a temp table so the FK update step has a fast lookup. We
    # intentionally avoid an in-Ruby Hash because rolling 10k rows
    # through `INSERT ... RETURNING id` per row is slow; a single SQL
    # INSERT-from-SELECT plus a join-based update for games is the
    # canonical pattern.
    execute(<<~SQL)
      CREATE TEMPORARY TABLE collection_to_bundle_map (
        old_collection_id BIGINT NOT NULL,
        new_bundle_id     BIGINT NOT NULL,
        PRIMARY KEY (old_collection_id)
      ) ON COMMIT DROP;
    SQL

    # Step 1: copy each collection row into bundles. We CTE the insert
    # + use RETURNING so the temp-table population happens in the same
    # statement. The slug-collision branch resolves at the WHERE NOT
    # EXISTS — colliding slugs get `-c-<collection_id>` appended which
    # is guaranteed unique because collection ids are unique. Friendly
    # id will normalize the slug on the next save of the bundle if
    # someone renames it.
    execute(<<~SQL)
      WITH new_rows AS (
        INSERT INTO bundles (
          name, slug, bundle_type,
          composite_cover_path, composite_cover_checksum,
          created_at, updated_at
        )
        SELECT
          c.name,
          CASE
            WHEN EXISTS (SELECT 1 FROM bundles b WHERE b.slug = c.slug)
              THEN substring(c.slug FROM 1 FOR 70) || '-c-' || c.id
            ELSE c.slug
          END,
          #{COLLECTION_BUNDLE_TYPE},
          c.composite_cover_path,
          c.composite_cover_checksum,
          c.created_at,
          NOW()
        FROM collections c
        ORDER BY c.id
        RETURNING id, slug, name
      )
      INSERT INTO collection_to_bundle_map (old_collection_id, new_bundle_id)
      SELECT c.id, n.id
      FROM collections c
      INNER JOIN new_rows n ON (
        n.slug = c.slug
        OR n.slug = substring(c.slug FROM 1 FOR 70) || '-c-' || c.id
      )
      WHERE c.name = n.name;
    SQL

    # Step 2: walk every games.collection_id and build the corresponding
    # bundle_members row. Position is assigned in alphabetical order
    # (LOWER(title)) within each bundle so the per-bundle iteration is
    # deterministic.
    execute(<<~SQL)
      INSERT INTO bundle_members (bundle_id, game_id, position, created_at, updated_at)
      SELECT
        m.new_bundle_id,
        g.id,
        (ROW_NUMBER() OVER (
          PARTITION BY m.new_bundle_id ORDER BY LOWER(g.title), g.id
        ) - 1)::int,
        NOW(),
        NOW()
      FROM games g
      INNER JOIN collection_to_bundle_map m ON m.old_collection_id = g.collection_id
      WHERE g.collection_id IS NOT NULL
      ORDER BY m.new_bundle_id, LOWER(g.title), g.id;
    SQL

    # Step 3: drop the FK, the column, the table.
    if foreign_key_exists?(:games, :collections)
      remove_foreign_key :games, :collections
    end
    if index_exists?(:games, :collection_id)
      remove_index :games, :collection_id
    end
    if column_exists?(:games, :collection_id)
      remove_column :games, :collection_id
    end
    drop_table :collections
  end

  def down
    # Recreate the collections table with the same schema as before
    # (mirrors BetaMigration3's create_table block).
    create_table :collections do |t|
      t.string   :composite_cover_checksum
      t.string   :composite_cover_path
      t.datetime :created_at, null: false
      t.string   :name, default: "Untitled collection", null: false
      t.string   :slug, null: false
      t.datetime :updated_at, null: false
      t.index    [ :name ], name: "index_collections_on_name"
      t.index    [ :slug ], name: "index_collections_on_slug", unique: true
    end

    add_column :games, :collection_id, :bigint
    add_index  :games, :collection_id, name: "index_games_on_collection_id"
    add_foreign_key :games, :collections

    # Bail out if there are no collection-typed bundles to roll back.
    return unless connection.select_value(
      "SELECT 1 FROM bundles WHERE bundle_type = #{COLLECTION_BUNDLE_TYPE} LIMIT 1"
    )

    # Reverse mapping temp table — bundle_id → recreated collection id.
    execute(<<~SQL)
      CREATE TEMPORARY TABLE bundle_to_collection_map (
        bundle_id        BIGINT NOT NULL,
        new_collection_id BIGINT NOT NULL,
        PRIMARY KEY (bundle_id)
      ) ON COMMIT DROP;
    SQL

    # Recreate one collection row per collection-typed bundle.
    execute(<<~SQL)
      WITH new_rows AS (
        INSERT INTO collections (name, slug, composite_cover_path,
                                 composite_cover_checksum,
                                 created_at, updated_at)
        SELECT b.name, b.slug, b.composite_cover_path,
               b.composite_cover_checksum, b.created_at, NOW()
        FROM bundles b
        WHERE b.bundle_type = #{COLLECTION_BUNDLE_TYPE}
        ORDER BY b.id
        RETURNING id, slug, name
      )
      INSERT INTO bundle_to_collection_map (bundle_id, new_collection_id)
      SELECT b.id, n.id
      FROM bundles b
      INNER JOIN new_rows n ON n.slug = b.slug AND n.name = b.name
      WHERE b.bundle_type = #{COLLECTION_BUNDLE_TYPE};
    SQL

    # Walk bundle_members for collection-typed bundles. The first
    # collection assignment wins per game (matches the original
    # single-pointer semantic — a game cannot belong to two collections).
    execute(<<~SQL)
      WITH first_membership AS (
        SELECT DISTINCT ON (bm.game_id)
               bm.game_id, m.new_collection_id
        FROM bundle_members bm
        INNER JOIN bundle_to_collection_map m ON m.bundle_id = bm.bundle_id
        ORDER BY bm.game_id, bm.bundle_id, bm.position
      )
      UPDATE games
      SET collection_id = fm.new_collection_id
      FROM first_membership fm
      WHERE games.id = fm.game_id;
    SQL

    # Tear down the collection-typed bundles + their bundle_members rows.
    execute(<<~SQL)
      DELETE FROM bundle_members
      WHERE bundle_id IN (
        SELECT id FROM bundles WHERE bundle_type = #{COLLECTION_BUNDLE_TYPE}
      );
    SQL
    execute(<<~SQL)
      DELETE FROM bundles WHERE bundle_type = #{COLLECTION_BUNDLE_TYPE};
    SQL
  end
end
