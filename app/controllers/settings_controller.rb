# frozen_string_literal: true

# Handles toggle endpoints for install-wide AppSetting flags.
# All actions require authentication (no allow_anonymous).
class SettingsController < ApplicationController
  # PATCH /settings/theme
  # Body: { theme: "<slug>" }
  # Validates the slug against the registry, persists it, then broadcasts
  # the updated #pito-settings element to pito:global so every open tab
  # picks up the new data-theme attribute without a reload.
  def theme
    slug = params[:theme].to_s

    unless Pito::Themes::Registry.find(slug)
      head :unprocessable_content
      return
    end

    AppSetting.theme = slug
    Pito::Stream::Broadcaster.broadcast_global_settings_update

    head :no_content
  end
end
