# frozen_string_literal: true

# P4 — `videos.view_count` moves onto the polymorphic `stats` table
# (`kind: "views"`), written by ImportVideosJob through `Pito::Stats.set`
# and read via `Video#view_count`.
class DropViewCountFromVideos < ActiveRecord::Migration[8.1]
  def up
    remove_column :videos, :view_count
  end

  def down
    add_column :videos, :view_count, :bigint, null: false, default: 0
  end
end
