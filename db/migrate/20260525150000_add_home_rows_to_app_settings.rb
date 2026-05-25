class AddHomeRowsToAppSettings < ActiveRecord::Migration[8.0]
  DEFAULT_HOME_ROWS = JSON.generate([
    { "cols" => 3, "panels" => [ "channels_overview", "latest_videos", "games_releasing" ] },
    { "cols" => 2, "panels" => [ "notifications_feed", "calendar" ], "ratios" => [ 40, 60 ] },
    {
      "cols" => 2,
      "panels" => [ "stack", { "stack" => [ "notifications", "security" ] } ],
      "ratios" => [ 60, 40 ]
    }
  ]).freeze

  def change
    add_column :app_settings, :home_rows, :text, default: DEFAULT_HOME_ROWS
  end
end
