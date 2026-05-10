# Phase 7 — Step C (7c-settings-youtube-ui.md). Settings → YouTube
# surface — list the user's GoogleIdentity (or empty state),
# render a connect button, list YouTube channels via
# `Youtube::Client#channels_list(mine: true)`, and let the user
# `[ connect ]` any of them into Pito's `Channel` table.
#
# Disconnect runs through the existing action-confirmation page
# framework (`shared/_action_screen.html.erb` +
# `DeletionsController#show` / `#destroy_youtube_connection`).
class Settings::YoutubeController < ApplicationController
  include GoogleOauthRedirect

  # GET /settings/youtube
  def show
    @identity = current_identity

    if @identity.nil? || @identity.needs_reauth?
      @youtube_channels = []
      @youtube_error = nil
    else
      load_youtube_channels
    end

    render :show
  end

  # POST /settings/youtube/connect — entry point for OmniAuth's
  # request phase. Stash the intent so the callback can route the
  # response back to /settings/youtube.
  def connect
    stash_youtube_connect_intent
    redirect_to "/auth/google_oauth2", allow_other_host: false,
                status: :see_other
  end

  # POST /settings/youtube/channels — connect a single YouTube
  # channel by its YouTube channel ID.
  def channels
    youtube_channel_id = params[:youtube_channel_id].to_s.strip
    if youtube_channel_id.blank?
      redirect_to settings_youtube_path,
                  alert: "missing youtube_channel_id."
      return
    end

    identity = current_identity
    if identity.nil? || identity.needs_reauth?
      redirect_to settings_youtube_path,
                  alert: "google account is not connected."
      return
    end

    channel_url = "https://www.youtube.com/channel/#{youtube_channel_id}"
    channel = Channel.find_or_initialize_by(channel_url: channel_url)

    if channel.new_record?
      channel.oauth_identity = identity
      channel.last_synced_at = Time.current
      channel.save!
    else
      # Existing row — only update the connection state. The
      # `prevent_url_change` guard would reject any channel_url
      # mutation; we never touch it.
      channel.update_columns(
        oauth_identity_id: identity.id,
        last_synced_at: Time.current
      )
    end

    redirect_to settings_youtube_path, notice: "connected."
  rescue Youtube::QuotaExhaustedError, Youtube::TransientError, Youtube::NeedsReauthError => e
    redirect_to settings_youtube_path,
                alert: "youtube api unavailable right now (#{e.class.name.demodulize}). try again."
  end

  private

  def current_identity
    return nil unless Current.user.present?

    GoogleIdentity.where(user_id: Current.user.id).order(last_authorized_at: :desc).first
  end

  def load_youtube_channels
    response = Youtube::Client.new(@identity).channels_list(
      mine: true,
      parts: %i[snippet statistics]
    )
    @youtube_channels = response[:items] || []
    @youtube_error = nil
  rescue Youtube::QuotaExhaustedError
    @youtube_channels = []
    @youtube_error = "quota exceeded"
  rescue Youtube::TransientError, Youtube::NeedsReauthError => e
    @youtube_channels = []
    @youtube_error = e.class.name.demodulize.gsub(/error\z/i, "").downcase
  end
end
