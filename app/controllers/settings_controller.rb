class SettingsController < ApplicationController
  OAUTH_KEYS = %w[youtube_client_id youtube_client_secret youtube_redirect_uri].freeze

  def index
    @settings = OAUTH_KEYS.index_with { |key| AppSetting.get(key) }
  end

  def update
    OAUTH_KEYS.each do |key|
      value = params.dig(:settings, key).presence
      if value
        AppSetting.set(key, value)
      end
    end
    redirect_to settings_path, notice: "settings saved."
  end
end
