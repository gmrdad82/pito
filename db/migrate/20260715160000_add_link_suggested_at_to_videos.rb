# frozen_string_literal: true

# Link suggestions (3.0.0) fire ONCE per vid at import while it's still
# unlinked — this timestamp is the once-only marker. NULL means "never
# suggested" (true of every pre-3.0.0 vid), so historical vids only pick up a
# suggestion if a future backfill decides to run one; nothing suggests to
# them automatically just because this column landed. A vid that's already
# linked never gets suggestions regardless of this column's value.
class AddLinkSuggestedAtToVideos < ActiveRecord::Migration[8.1]
  def change
    add_column :videos, :link_suggested_at, :datetime
  end
end
