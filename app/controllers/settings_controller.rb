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

  # PATCH /settings/ai
  # Body (any subset): { provider:, api_key:, clear_key:, model: }
  # Backs the /config ai picker dialog. The API key lands in the AppSetting
  # key/value store, whose `value` column is encrypted at rest; it is never
  # echoed back — responses only carry `key_present`. `clear_key: true` removes
  # the stored key. A model choice is validated against the provider's catalog
  # (live list ∪ pinned fallback) so a stale picker can't persist a ghost model.
  def ai
    provider = (params[:provider].presence || "opencode").to_s

    begin
      Ai::ProviderRegistry.provider(provider.to_sym)
    rescue KeyError
      return render json: { error: "unknown_provider" }, status: :unprocessable_content
    end

    if params[:clear_key].present?
      AppSetting.set("#{provider}_api_key", nil)
    elsif params[:api_key].present?
      AppSetting.set("#{provider}_api_key", params[:api_key].to_s.strip)
    end

    if params[:model].present?
      model = params[:model].to_s
      known = Ai::ModelCatalog.models(provider: provider.to_sym).any? { |m| m[:id] == model }
      return render json: { error: "unknown_model" }, status: :unprocessable_content unless known

      AppSetting.set("ai_model", model)
      AppSetting.set("ai_provider", provider)
    end

    render json: {
      provider:    provider,
      model:       AppSetting.get("ai_model"),
      key_present: AppSetting.get("#{provider}_api_key").present?
    }
  end
end
