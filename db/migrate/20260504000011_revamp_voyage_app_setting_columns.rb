# Phase 4 §3.5 (2026-05-04 Phase B revamp) — Voyage AppSetting reshape.
#
# Replaces the single `voyage_embeddings_enabled` Boolean with two columns:
#
# 1. `voyage_api_key` (text, encrypted via Active Record Encryption) — the
#    Voyage AI API key, UI-editable so the user can rotate keys without a
#    deploy. Text (not string) because AR Encryption ciphertext can run past
#    255 chars depending on the encryptor configuration. Nullable; the seed
#    bootstrap (db/seeds.rb) populates it from
#    Rails.application.credentials.dig(:voyage, env, :api_key) on first run,
#    after which the UI becomes the authoritative source.
#
# 2. `voyage_index_project_notes` (boolean, default false, NOT NULL) — the
#    per-target gate for project-notes indexing. Future indexing targets
#    (e.g. videos, channels) get their own boolean columns when those
#    surfaces ship; the previous single Boolean was too coarse.
#
# Removes `voyage_embeddings_enabled`. Reversible — `remove_column` is given
# the type so the down migration restores the column with its prior shape.
class RevampVoyageAppSettingColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :voyage_api_key, :text
    add_column :app_settings, :voyage_index_project_notes, :boolean,
               null: false, default: false
    remove_column :app_settings, :voyage_embeddings_enabled, :boolean,
                  null: false, default: false
  end
end
