# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). Settings → YouTube surface — list the user's
# YoutubeConnection (or empty state), render a connect button, list
# YouTube channels via `Youtube::Client#channels_list(mine: true)`,
# and let the user `[ connect ]` any of them into pito's `Channel`
# table.
#
# Disconnect runs through the existing action-confirmation page
# framework (`shared/_action_screen.html.erb` +
# `DeletionsController#show` / `#destroy_youtube_connection`).
class Settings::YoutubeController < ApplicationController
  include YoutubeConnectionOauthRedirect

  # GET /settings/youtube
  def show
    @youtube_connection = current_youtube_connection

    if @youtube_connection.nil? || @youtube_connection.needs_reauth?
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

  # POST /settings/youtube/channels — connect one or more YouTube
  # channels picked from the multi-select form on the manage page.
  #
  # Accepts either `youtube_channel_ids[]` (array of UC… IDs from
  # the checkbox form) or the legacy single `youtube_channel_id`
  # scalar (kept for backwards-compatibility with the CLI's older
  # submit shape; deprecated for the web flow). Already-linked
  # channels are filtered server-side: posting a UC id that is
  # already linked to this connection is a no-op (no duplicate
  # create, no flash error), so a stale form submission can't
  # bypass the "already added" UI guard.
  def channels
    requested_ids = Array(params[:youtube_channel_ids]).map { |s| s.to_s.strip }
    requested_ids << params[:youtube_channel_id].to_s.strip if params[:youtube_channel_id].present?
    requested_ids = requested_ids.reject(&:blank?).uniq

    if requested_ids.empty?
      redirect_to settings_youtube_path,
                  alert: "select at least one channel to add."
      return
    end

    connection = current_youtube_connection
    if connection.nil? || connection.needs_reauth?
      redirect_to settings_youtube_path,
                  alert: "google account is not connected."
      return
    end

    added_count = 0
    requested_ids.each do |youtube_channel_id|
      channel_url = "https://www.youtube.com/channel/#{youtube_channel_id}"
      channel = Channel.find_or_initialize_by(channel_url: channel_url)

      if channel.new_record?
        channel.youtube_connection = connection
        channel.last_synced_at = Time.current
        channel.save!
        added_count += 1
      elsif channel.youtube_connection_id != connection.id
        # Existing row not linked to this connection — link it. The
        # `prevent_url_change` guard would reject any channel_url
        # mutation; we never touch it.
        channel.update_columns(
          youtube_connection_id: connection.id,
          last_synced_at: Time.current
        )
        added_count += 1
      end
      # else: already linked to this connection — no-op, the form
      # guard should have prevented this submit anyway.
    end

    if added_count.zero?
      redirect_to settings_youtube_path,
                  notice: "no new channels added (already linked)."
    else
      noun = added_count == 1 ? "channel" : "channels"
      redirect_to channels_path,
                  notice: "#{added_count} #{noun} added."
    end
  rescue Youtube::QuotaExhaustedError, Youtube::TransientError, Youtube::NeedsReauthError => e
    redirect_to settings_youtube_path,
                alert: "youtube api unavailable right now (#{e.class.name.demodulize}). try again."
  end

  private

  def current_youtube_connection
    return nil unless Current.user.present?

    YoutubeConnection.where(user_id: Current.user.id).order(last_authorized_at: :desc).first
  end

  def load_youtube_channels
    response = Youtube::Client.new(@youtube_connection).channels_list(
      mine: true,
      parts: %i[snippet statistics]
    )
    @youtube_channels = response[:items] || []
    @youtube_error = nil
  rescue Youtube::QuotaExhaustedError
    @youtube_channels = []
    @youtube_error = "quota exceeded"
  rescue Youtube::NeedsReauthError => e
    # The client may have just flipped `needs_reauth: true` on the
    # connection row (insufficient-scopes 403 or 401 after refresh).
    # Reload the in-memory object so the view's `needs_reauth?` check
    # renders the [reconnect] banner instead of "youtube api
    # unavailable" — the latter is misleading; this is an auth-state
    # problem the user can fix, not a transient outage.
    @youtube_connection.reload
    @youtube_channels = []
    @youtube_error = e.class.name.demodulize.gsub(/error\z/i, "").downcase
  rescue Youtube::TransientError => e
    @youtube_channels = []
    @youtube_error = e.class.name.demodulize.gsub(/error\z/i, "").downcase
  end
end
