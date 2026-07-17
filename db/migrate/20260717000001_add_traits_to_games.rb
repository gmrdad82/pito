# frozen_string_literal: true

# Traits storage — the owner's game-judgment ontology (see
# traits-design.md, config/pito/traits.yml). One jsonb
# column carries the whole shape (schema_version / values / sources /
# classified_at — Game::Traits::Vocabulary validates it); `{}` IS the valid
# "unclassified" state, so default {} + NOT NULL means every reader can skip
# a nil guard.
#
# Additive with a constant default: single deploy, no backfill phase, no
# table rewrite (Postgres fills existing rows from the default without
# touching each one). GIN index mirrors the alternative_names/themes/
# player_perspectives precedent already on this table — nothing queries
# jsonb containment on `traits` yet, but the index is cheap to carry from day
# one and this migration is the natural place to add it.
class AddTraitsToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :traits, :jsonb, default: {}, null: false
    add_index  :games, :traits, using: :gin
  end
end
