class ReshapeHomeRowsDropChannelsVideos < ActiveRecord::Migration[8.0]
  # Removes "channels_overview" and "latest_videos" from any row's panels
  # array in the AppSetting home_rows JSON column. Collapses remaining slots
  # and adjusts `cols` to match the new panel count. Drops rows that become
  # empty after the removal. This is a one-way migration; `down` is a no-op
  # because the two panels have been deleted from the codebase.
  def up
    AppSetting.find_each do |s|
      next unless s.home_rows.present?
      rows = JSON.parse(s.home_rows)
      rows.each do |row|
        next unless row.is_a?(Hash) && row["panels"].is_a?(Array)
        row["panels"].reject! { |p| p == "channels_overview" || p == "latest_videos" }
        row["cols"] = row["panels"].length if row["panels"].any?
      end
      rows.reject! { |r| r.is_a?(Hash) && r["panels"].is_a?(Array) && r["panels"].empty? }
      s.update_column(:home_rows, rows.to_json)
    end
  end

  def down
    # no-op — panels have been removed from the codebase
  end
end
