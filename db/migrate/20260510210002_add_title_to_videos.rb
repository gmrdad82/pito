# Phase 7.5 — Step 11a (Channel Schema + Sync Foundation).
#
# Intentional no-op. The 11a spec stipulates: "If a later phase already
# added it, this migration becomes a no-op and the implementation agent
# reports back rather than silently skipping."
#
# At dispatch time, `videos.title` already exists on schema as
# `string, limit: 100, default: "", null: false` — added by the Phase
# 12 video schema expansion (`20260510135730_expand_videos_for_data_api_v3`).
# The 11a spec preferred a nullable column ("rendered as 'untitled' when
# nil"), but the existing column with empty-string default is
# semantically equivalent for the preview's "untitled placeholder"
# behavior — Video presenters render "untitled" on blank as well as nil.
#
# Per project rule, migrations stay reversible; this `change` block is
# trivially reversible (no operations on either direction).
class AddTitleToVideos < ActiveRecord::Migration[8.1]
  def change
    # No-op — videos.title pre-exists on schema. See comment block above.
  end
end
