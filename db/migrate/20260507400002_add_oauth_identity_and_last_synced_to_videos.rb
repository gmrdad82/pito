# Phase 7 Path A2 (literal full retract). Adds the columns Video keeps
# from Phase 7's Channel/Video shape:
#
#   - `oauth_identity_id` — which Google identity authorized the sync
#     that produced this Video row. FK to `google_identities`, nullable.
#   - `star` — favorite flag, mirrors the Channel.star surface.
#
# The `last_synced_at` column already exists on `videos` from a Phase 4
# placeholder migration; we leave it in place. All three columns are
# nullable / default false; seed data leaves the new ones untouched.
# The connect-channel sync flow (Phase 8+) populates them when it
# lands.
class AddOauthIdentityAndLastSyncedToVideos < ActiveRecord::Migration[8.1]
  def change
    add_reference :videos,
                  :oauth_identity,
                  type: :bigint,
                  null: true,
                  foreign_key: { to_table: :google_identities }

    add_column :videos, :star, :boolean, null: false, default: false

    add_index :videos, [ :tenant_id, :star ]
  end
end
