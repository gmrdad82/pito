# frozen_string_literal: true

# Staged edits for a YouTube video. Never mutates `Video` directly —
# see `/update videos` (P33) which pushes the preview to the YouTube
# Data API, then re-imports the video to refresh the mirror.
class VideoPreview < ApplicationRecord
  # ── Associations ──────────────────────────────────────────────
  belongs_to :video

  has_one_attached :thumbnail

  # ── Enums ─────────────────────────────────────────────────────
  enum :status, {
    draft:      0,
    publishing: 1,
    published:  2,
    failed:     3
  }

  # Shorts remixing: what level of remixing the viewer is allowed.
  # Uses `prefix: true` so predicate names are
  # `shorts_remixing_video_audio?` / `shorts_remixing_audio_only?` /
  # `shorts_remixing_none?` — avoiding conflict with AR::Base#none.
  enum :shorts_remixing, {
    video_audio: 0,
    audio_only:  1,
    none:        2
  }, prefix: true

  # ── Validations ───────────────────────────────────────────────
  validates :status, presence: true
end
