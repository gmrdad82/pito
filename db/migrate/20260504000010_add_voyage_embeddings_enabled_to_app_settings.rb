# Phase 4 §3.5 (2026-05-04 amendment, post-review refinement) — Voyage call
# gating pivots from `Rails.application.config.voyage_embeddings_enabled`
# (set in `config/application.rb`, requires a Rails restart to flip) to a
# DB-backed Boolean column on `app_settings`. Phase B's Settings UI flips it
# at runtime; Notes::EmbedJob reads `AppSetting.voyage_embeddings_enabled?`.
#
# Defaults to `false` so dev/test never fire Voyage HTTP calls on dummy
# data. Production seeds set it to `true` (see `db/seeds.rb`).
#
# Reversible.
class AddVoyageEmbeddingsEnabledToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :voyage_embeddings_enabled, :boolean,
               null: false, default: false
  end
end
