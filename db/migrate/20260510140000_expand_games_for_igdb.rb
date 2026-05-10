# Phase 14 §1 — Game Data Model + IGDB v4 Client.
#
# Adds the IGDB-sourced columns + local-only columns to `games`.
# Phase 4 legacy columns (`publisher` string, `platforms` jsonb) are
# kept until the post-Phase-14 polish window — see spec Q11. New
# code does NOT read or write them.
#
# `manual_date_override` already lives on `games` (Phase 15 §1
# pre-landed it). This migration is decoupled from that and from
# the `platform_owned_id` FK (added separately so the schema dump
# stays auditable).
class ExpandGamesForIgdb < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :igdb_id,                   :bigint
    add_column :games, :igdb_slug,                 :string
    add_column :games, :igdb_checksum,             :string
    add_column :games, :summary,                   :text
    add_column :games, :cover_image_id,            :string
    add_column :games, :release_date,              :date
    add_column :games, :release_year,              :integer
    add_column :games, :igdb_rating,               :decimal, precision: 5, scale: 2
    add_column :games, :igdb_rating_count,         :integer
    add_column :games, :aggregated_rating,         :decimal, precision: 5, scale: 2
    add_column :games, :aggregated_rating_count,   :integer
    add_column :games, :total_rating,              :decimal, precision: 5, scale: 2
    add_column :games, :total_rating_count,        :integer
    add_column :games, :external_steam_app_id,     :string
    add_column :games, :external_gog_id,           :string
    add_column :games, :external_epic_id,          :string
    add_column :games, :ttb_main_seconds,          :integer
    add_column :games, :ttb_extras_seconds,        :integer
    add_column :games, :ttb_completionist_seconds, :integer
    # Local-only — survives re-sync. FK + index follow once `platforms`
    # table exists.
    add_column :games, :platform_owned_id,         :bigint
    add_column :games, :played_at,                 :date
    add_column :games, :notes,                     :text
    add_column :games, :hours_of_footage_cached,   :integer
    add_column :games, :hours_of_footage_manual,   :integer
    add_column :games, :igdb_synced_at,            :datetime
    add_column :games, :last_sync_error,           :text

    add_index :games, :igdb_id,               unique: true, where: "igdb_id IS NOT NULL"
    add_index :games, :igdb_slug,             unique: true, where: "igdb_slug IS NOT NULL"
    add_index :games, :release_year
    add_index :games, :external_steam_app_id, where: "external_steam_app_id IS NOT NULL"
    add_index :games, :platform_owned_id
    add_index :games, :igdb_synced_at
  end
end
