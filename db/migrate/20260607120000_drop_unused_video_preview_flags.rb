class DropUnusedVideoPreviewFlags < ActiveRecord::Migration[8.1]
  # These 8 booleans were scaffolded onto `video_previews` but never wired
  # into any form, sync, or publish path (zero references in app/ + lib/).
  # The deferred `/update videos` publish path (P33) uses differently-named
  # fields (`self_declared_made_for_kids`, `contains_synthetic_media`, …),
  # not these — so these are pure dead scaffolding. All nullable, no data.
  def change
    remove_column :video_previews, :allow_embedding,          :boolean
    remove_column :video_previews, :automatic_chapters,       :boolean
    remove_column :video_previews, :automatic_concepts,       :boolean
    remove_column :video_previews, :automatic_places,         :boolean
    remove_column :video_previews, :contains_altered_content, :boolean
    remove_column :video_previews, :made_for_kids,            :boolean
    remove_column :video_previews, :notify_subscribers,       :boolean
    remove_column :video_previews, :paid_promotion,           :boolean
  end
end
