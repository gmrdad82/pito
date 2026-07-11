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
  # Body (any subset): { provider:, api_key:, clear_key:, model:, effort:, favorite: }
  # Backs the /config ai picker dialog. The API key lands in the AppSetting
  # key/value store, whose `value` column is encrypted at rest; it is never
  # echoed back — responses only carry `key_present`. `clear_key: true` removes
  # the stored key. A model choice is validated against the provider's catalog
  # (live list ∪ pinned fallback) so a stale picker can't persist a ghost model,
  # and stamps the recents list. `favorite` toggles a "provider/model" pin;
  # `effort` sets low|medium|high (or "off" to clear) FOR THE ACTIVE MODEL —
  # effort is a per-model map, never a global switch. Model writes land before
  # effort writes so a combined request binds effort to the new model.
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

    AppSetting.toggle_ai_favorite(params[:favorite].to_s) if params[:favorite].present?

    if params[:model].present?
      model = params[:model].to_s
      known = Ai::ModelCatalog.models(provider: provider.to_sym).any? { |m| m[:id] == model }
      return render json: { error: "unknown_model" }, status: :unprocessable_content unless known

      AppSetting.set("ai_model", model)
      AppSetting.set("ai_provider", provider)
      AppSetting.push_ai_recent("#{provider}/#{model}")
    end

    if params[:effort].present?
      effort = params[:effort].to_s
      return render json: { error: "unknown_effort" }, status: :unprocessable_content unless %w[low medium high off].include?(effort)
      return render json: { error: "no_model" }, status: :unprocessable_content if active_model_entry.nil?

      AppSetting.set_ai_effort(active_model_entry, effort)
    end

    render json: {
      provider:    provider,
      model:       AppSetting.get("ai_model"),
      key_present: AppSetting.get("#{provider}_api_key").present?,
      effort:      active_model_entry && AppSetting.ai_effort_for(active_model_entry),
      favorites:   AppSetting.ai_favorites,
      recents:     AppSetting.ai_recents
    }
  end

  private

  # "provider/model" for the currently ACTIVE selection, or nil before any
  # model has been picked — the key of the per-model effort map.
  def active_model_entry
    model = AppSetting.get("ai_model").presence
    return nil if model.nil?

    "#{AppSetting.get("ai_provider").presence || "opencode"}/#{model}"
  end
end
