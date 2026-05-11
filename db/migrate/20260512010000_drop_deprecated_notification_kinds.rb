# 2026-05-12 — Drop two notification kinds per user direction.
#
# `video_pre_publish_check_missed` (kind enum 1) and
# `game_release_upcoming` (kind enum 2) are removed from the app. The
# emission paths (NotificationSource service, formatter templates,
# dispatch-declaration entries, calendar pre-release reminder copy) are
# deleted in the same patch.
#
# The enum values stay in `Notification` as deprecated-but-reserved so
# future kinds don't collide on integers 1 / 2. This migration is
# purely a data wipe — it deletes any in-flight rows of those kinds so
# the model never tries to load an integer that no longer has a Ruby
# label.
#
# Idempotent: re-running deletes 0 rows on a clean DB.
class DropDeprecatedNotificationKinds < ActiveRecord::Migration[8.1]
  def up
    transaction do
      execute(<<~SQL)
        DELETE FROM notifications
        WHERE kind IN (1, 2)
      SQL
    end
  end

  def down
    # No-op: the dropped rows carried event_payload shapes tied to
    # removed templates / source helpers. Restoring them would not
    # reconstitute a working notification anyway. Migration reversal is
    # a metadata-only step.
  end
end
