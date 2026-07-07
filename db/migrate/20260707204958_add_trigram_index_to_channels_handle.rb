# frozen_string_literal: true

# Backs fuzzy `show channel <handle>` resolution (#7). The exact lookup and the
# fuzzy fallback both normalize the handle as REPLACE(handle, '@', '') — so the
# trigram index is on that same expression (pg_trgm folds case, no LOWER needed),
# letting `REPLACE(handle,'@','') % :q` and `similarity(...)` use the GIN index.
# Mirrors index_games_on_title_trigram / index_videos_on_title_trigram (which use
# plain-column trigram indexes; channels needs the expression form because the
# lookup strips the leading @). Raw SQL because Rails' opclass: option is not
# applied to expression indexes.
class AddTrigramIndexToChannelsHandle < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      CREATE INDEX index_channels_on_normalized_handle_trigram
      ON channels USING gin ((REPLACE(handle, '@', '')) gin_trgm_ops)
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_channels_on_normalized_handle_trigram"
  end
end
