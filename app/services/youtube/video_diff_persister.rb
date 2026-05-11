# Phase 23 — Step 23a (Video Sync + Diff Dialog).
#
# Persists the output of `Youtube::DiffComputer` into a `VideoDiff`
# row. Idempotent: if an open diff already exists for the video, the
# payload is replaced and the row stays open (no new row spawned). On
# empty diff, no row is written.
#
# Always stamps `videos.last_diff_checked_at` to reflect the last
# pass — even on empty-diff runs, so the daily job's "everything's
# in sync" signal is recorded.
#
# Returns the persisted `VideoDiff` row, or `nil` when the diff is
# empty.
module Youtube
  module VideoDiffPersister
    module_function

    def call(video:, diff_hash:, detected_at: Time.current)
      video.update_columns(last_diff_checked_at: detected_at)

      if diff_hash.blank?
        return nil
      end

      diff = VideoDiff.open.find_by(video_id: video.id)

      if diff
        diff.update!(payload: diff_hash, detected_at: detected_at)
      else
        diff = VideoDiff.create!(
          video: video,
          payload: diff_hash,
          detected_at: detected_at
        )
      end

      diff
    end
  end
end
