# Phase 7 — Step C (7c-settings-youtube-ui.md) — link channels to the
# Google identity that authorized them.
#
# The existing `connected` boolean on `channels` (Phase 4 placeholder)
# stays in place — this migration only adds the FK to
# `google_identities`. After Phase 7C ships, "connected" means
# "`oauth_identity_id` is set"; the existing column remains the
# user-facing flag (the disconnect flow flips both back).
class AddOauthIdentityToChannels < ActiveRecord::Migration[8.1]
  def change
    add_reference :channels,
                  :oauth_identity,
                  type: :bigint,
                  null: true,
                  foreign_key: { to_table: :google_identities }

    # Disconnect flow asks "is anyone else still using this identity?";
    # the partial index on connected channels keeps the lookup O(log
    # connected) regardless of disconnected-history volume.
    add_index :channels,
              [ :tenant_id, :oauth_identity_id ],
              name: "index_channels_on_tenant_id_and_oauth_identity_id"
  end
end
