class AddTenantIdToVideoUploads < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 1 of 3 for video_uploads.

  def up
    add_reference :video_uploads, :tenant, null: true, foreign_key: true, index: true
  end

  def down
    remove_reference :video_uploads, :tenant, foreign_key: true
  end
end
