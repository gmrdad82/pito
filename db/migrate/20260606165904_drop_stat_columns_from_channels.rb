# frozen_string_literal: true

# P4 — Move channel counters off dedicated columns onto the polymorphic
# `stats` table. `channels.watched_hours` is dropped outright (Analytics-
# sourced; returns with a future Pito::Analytics). `subscriber_count` and
# `view_count` now live in `stats`, read/written through `Pito::Stats`.
#
# (videos.view_count is dropped in a later migration alongside its
# writer's repoint.)
class DropStatColumnsFromChannels < ActiveRecord::Migration[8.1]
  def up
    remove_column :channels, :subscriber_count
    remove_column :channels, :view_count
    remove_column :channels, :watched_hours
  end

  def down
    add_column :channels, :subscriber_count, :bigint
    add_column :channels, :view_count, :bigint
    add_column :channels, :watched_hours, :bigint
  end
end
