class SettingsController < ApplicationController
  OAUTH_KEYS = %w[youtube_client_id youtube_client_secret youtube_redirect_uri].freeze
  GENERAL_KEYS = %w[max_panes].freeze

  def index
    @settings = (OAUTH_KEYS + GENERAL_KEYS).index_with { |key| AppSetting.get(key) }
    @max_panes_default = ENV.fetch("MAX_PANES", 3).to_i
  end

  def update
    OAUTH_KEYS.each do |key|
      value = params.dig(:settings, key).presence
      AppSetting.set(key, value) if value
    end

    GENERAL_KEYS.each do |key|
      value = params.dig(:settings, key).presence
      if value
        AppSetting.set(key, value)
      end
    end

    redirect_to settings_path, notice: "settings saved."
  end
end
