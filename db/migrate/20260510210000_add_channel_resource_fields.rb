# Phase 7.5 — Step 11a (Channel Schema + Sync Foundation).
#
# Adds the Channel resource columns the Phase 11 management surface
# needs to display and (in 11c) mutate. All columns are nullable / have
# safe defaults so the migration is non-blocking for the existing
# Path A2 thin Channel rows. The watermark surface intentionally
# omits a `watermark_position` column per parent spec D21 — YouTube
# only supports the right-hand corner.
class AddChannelResourceFields < ActiveRecord::Migration[8.1]
  def change
    change_table :channels do |t|
      # Snippet (channels.list#snippet).
      t.string  :title
      t.string  :handle
      t.text    :description
      t.string  :country, limit: 2           # ISO 3166-1 alpha-2.
      t.string  :default_language, limit: 10 # BCP-47 tag.

      # Branding settings (channels.list#brandingSettings).
      t.text    :keywords
      t.string  :banner_url
      t.string  :avatar_url
      t.string  :watermark_url
      # Enum-as-string. Values: always / entire_video /
      # offset_from_start / offset_from_end. Validated at the model
      # layer for portability; no DB CHECK constraint.
      t.string  :watermark_timing
      t.integer :watermark_offset_ms

      # JSON array of `{ title, url }` objects. Cached from the
      # branding settings shape; 11c populates fully via the edit form.
      t.jsonb   :links, default: [], null: false

      # Statistics (channels.list#statistics).
      t.bigint  :subscriber_count
      t.bigint  :view_count
      t.integer :video_count
      # Hidden-subscriber-count flag from the API. When true, the
      # `subscriber_count` value is the API's reported zero / nil and
      # the UI renders "Hidden" instead.
      t.boolean :hidden_subscriber_count, default: false, null: false

      # Snippet timestamps.
      t.datetime :published_at

      # Pito-side 14-day rate-limit gate. Stamped by the (future) edit
      # path when the user pushes a title / handle change to YouTube.
      t.datetime :title_changed_at
      t.datetime :handle_changed_at
    end

    # Uniqueness NOT enforced here — YouTube handles can collide across
    # deleted-then-reused namespaces. The index is a lookup helper only.
    add_index :channels, :handle, where: "handle IS NOT NULL"
  end
end
