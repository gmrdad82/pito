# Phase 23 — Step 23a (Video Sync + Diff Dialog).
#
# Adds the writable + display-only Video columns the diff dialog needs.
# Many of the spec's enumerated fields ALREADY exist from Phase 12
# (Phase 12 §"ExpandVideosForDataApiV3") — `title`, `description`,
# `tags`, `category_id`, `privacy_status`, `publish_at`, `published_at`,
# `self_declared_made_for_kids`, `contains_synthetic_media`,
# `made_for_kids_effective`, `etag`, `thumbnail_url`, `duration_seconds`,
# `last_sync_error`. This migration audits the live schema and only adds
# what's missing:
#
#   - `embeddable` (status) — boolean default true.
#   - `public_stats_viewable` (status) — boolean default true.
#   - `view_count` / `like_count` / `comment_count` (statistics) —
#     bigint default 0, display-only.
#   - `title_changed_at` (datetime) — see Q1 research outcome: YouTube
#     does NOT enforce a 14-day cooldown on video title updates the way
#     it does for channels. The column is added per locked Q1 ("populate
#     but inert") so the audit trail still records when the title was
#     last pushed to YouTube. No `title_locked?` gate ships.
#   - `last_diff_checked_at` (datetime) — last time the daily diff job
#     touched this video.
class AddVideoMetadataColumnsForDiff < ActiveRecord::Migration[8.1]
  def change
    add_column :videos, :embeddable, :boolean, default: true, null: false
    add_column :videos, :public_stats_viewable, :boolean, default: true, null: false

    # Display-only counters. bigint because YouTube view counts on viral
    # videos exceed 2^31 (the Phpsiao limit). Default 0 so the diff
    # computer can compare counts without nil checks.
    add_column :videos, :view_count, :bigint, default: 0, null: false
    add_column :videos, :like_count, :bigint, default: 0, null: false
    add_column :videos, :comment_count, :bigint, default: 0, null: false

    # Q1 outcome: inert. Stamped on Pito-wins title apply for audit;
    # NOT used to gate the form / disable inputs.
    add_column :videos, :title_changed_at, :datetime
    add_column :videos, :last_diff_checked_at, :datetime
  end
end
