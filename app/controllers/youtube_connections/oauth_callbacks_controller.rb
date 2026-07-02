# Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). Google OAuth callback handler — narrowed to the
# YouTube-connection flow only.
#
# The single endpoint at `/auth/youtube/callback` (registered in the
# Google Cloud Console) handles ONLY the YouTube-connect flow
# (intent = "youtube_connect"; kicked off by `/connect`). The sign-in
# branch is permanently retired per ADR 0006: pito will never
# offer sign-in-with-Google.
#
# Any callback hitting `/auth/youtube/callback` without the
# `youtube_connect` intent in session is treated as a stale / replayed
# callback and redirected to the failure path with a generic flash
# explaining that sign-in via Google is not supported.
#
# State parameter validation is OmniAuth's responsibility — the
# `omniauth-google-oauth2` gem turns it on by default and OmniAuth
# rejects mismatched state with `omniauth.error.type = :csrf_detected`
# before this controller runs. We surface that as a clean redirect
# to /auth/failure with a flash.
class YoutubeConnections::OauthCallbacksController < ApplicationController
  include YoutubeConnectionOauthRedirect


  # `failure` is allowed before sign-in (auth flow can fail upstream
  # of any session creation). `create` is NOT allow_anonymous: the
  # YouTube-connect path expects an active session (the user was signed
  # in to pito BEFORE clicking [ connect ]; the cookie stays through
  # the OAuth round-trip because the redirect bounces through the same
  # domain). Z1: Current.user is gone; guard is now Current.session.
  allow_anonymous :failure

  # OmniAuth's middleware does its own state-parameter check before
  # the controller runs; the callback is a server-to-server return
  # from Google so the CSRF token round-trip does not apply.
  skip_before_action :verify_authenticity_token, only: %i[create failure]

  # GET (or POST) /auth/youtube/callback
  def create
    auth_hash = request.env["omniauth.auth"]
    intent = consume_oauth_intent

    if auth_hash.nil? || request.env["omniauth.error"].present?
      audit("youtube_connection.callback.failed",
            reason: omniauth_failure_reason(request.env["omniauth.error"]))
      return redirect_to(youtube_connection_oauth_failure_path,
                         alert: failure_message(request.env["omniauth.error"]))
    end

    if intent != YOUTUBE_CONNECT_INTENT
      # No sign-in branch exists post-ADR 0006. Any callback without
      # the `youtube_connect` intent is stale / replayed.
      audit("youtube_connection.callback.stale_intent",
            intent: intent.to_s.presence)
      return redirect_to(youtube_connection_oauth_failure_path,
                         alert: t("pito.youtube_connections.callback.stale_intent"))
    end

    # Consume the conversation UUID stashed by ChatController#handle_connect.
    # Used to persist a result Event and to redirect back to the chat.
    conversation_uuid = consume_connect_conversation_uuid
    conversation = conversation_uuid.present? ? Conversation.find_by(uuid: conversation_uuid) : nil

    connection = upsert_youtube_connection_for_current_user(auth_hash)
    if connection.nil?
      audit("youtube_connection.callback.failed", reason: "no_active_session")
      return redirect_to(youtube_connection_oauth_failure_path,
                         alert: t("pito.youtube_connections.callback.session_expired"))
    end

    missing = missing_required_scopes(connection)
    if missing.any?
      # Partial grant — Google's consent screen lets the user uncheck
      # individual scopes, so a "success" callback can still leave the
      # token unable to drive the YouTube surfaces. Flip needs_reauth
      # back on (the upsert defaulted it false) and explain in flash.
      connection.update_columns(needs_reauth: true)
      audit("youtube_connection.callback.partial_grant",
            connection_id: connection.id,
            missing_scopes: missing)
      persist_connect_result(conversation, t("pito.youtube_connections.callback.partial_grant"), connection:)
      return redirect_to(conversation ? conversation_path(uuid: conversation.uuid) : root_path)
    end

    audit("youtube_connection.callback.succeeded",
          connection_id: connection.id)

    # Recovery hook (0.9.0 Phase RQ): this callback just flipped a previously
    # dead grant back to life — requeue failed jobs + catch up the scheduled
    # passes the flag made every job skip. Dirty tracking (not a plain flag
    # read) so a FIRST connect never triggers it; the partial-grant branch
    # returned above, so a still-broken grant can't reach this.
    if connection.saved_change_to_needs_reauth? && connection.needs_reauth_before_last_save
      YoutubeReauthRecoveryJob.perform_later(connection.id)
    end

    # Channel discovery — auto-links all channels accessible under this
    # Google account. Duplicates (by youtube_channel_id) are skipped.
    # API failures surface as a flash note but do NOT roll back the
    # connection — the user can re-run /connect to retry discovery.
    discovery = discover_and_link_channels(connection)
    message   = compose_callback_flash(discovery)
    # "Already connected / nothing new" is informational, not an error — emit it
    # as a Standard (:system) message so it's the right colour AND renders its
    # HTML (the payload carries html: true; ErrorComponent would escape it).
    persist_connect_result(conversation, message, kind: :system, connection:,
                           import_videos: Array(discovery[:added]).any?)
    redirect_to(conversation ? conversation_path(uuid: conversation.uuid) : root_path)
  end

  # GET /auth/failure
  def failure
    @reason = params[:message].to_s.presence || "auth_failed"
    flash.now[:alert] ||= t("pito.youtube_connections.callback.auth_failed", reason: @reason)
    render plain: t("pito.youtube_connections.callback.auth_failed", reason: @reason),
           status: :unauthorized
  end

  private

  # Persist a result Event on the conversation. For successful connects
  # (kind: :system), the turn stays open so a background job can append
  # channel stats later. Errors and partial grants complete immediately.
  def persist_connect_result(conversation, message, kind: :system, connection: nil, import_videos: false)
    return unless conversation
    return if message.blank?

    turn = conversation.turns.where(completed_at: nil).order(:position).last ||
           conversation.turns.create!(
             position:   Turn.next_position_for(conversation),
             input_kind: :slash,
             input_text: "/connect"
           )

    payload = { text: message, html: true }
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(
      turn:,
      kind:    kind,
      payload: payload
    )

    if kind == :system && connection.present?
      # Multi-stage flow: keep turn open, enqueue channel info job (stage 1).
      # import_videos: true only when new channels were actually added this callback
      # (false for re-auths where discovery returned only duplicates).
      ChannelInfoJob.perform_later(connection.id, turn.id, import_videos: import_videos)
    else
      # Error / partial grant: complete immediately
      turn.update_columns(completed_at: Time.current)
    end
  end

  # Find or create the YoutubeConnection row for `Current.user` keyed
  # on `google_subject_id` (install-wide unique). Returns nil if no
  # current user is in scope (the connect flow expects a logged-in
  # pito user).
  def upsert_youtube_connection_for_current_user(auth_hash)
    # Z1: User model gone; guard on active session instead.
    return nil unless Current.session.present?

    info = auth_hash.respond_to?(:info) ? auth_hash.info : auth_hash["info"] || {}
    creds = auth_hash.respond_to?(:credentials) ? auth_hash.credentials : auth_hash["credentials"] || {}
    extra_raw = auth_hash.respond_to?(:extra) ? auth_hash.extra : auth_hash["extra"] || {}

    subject_id = (auth_hash["uid"] || (auth_hash.respond_to?(:uid) ? auth_hash.uid : nil)).to_s
    granted_scopes = parse_granted_scopes(extra_raw, creds)

    connection = YoutubeConnection.find_or_initialize_by(
      google_subject_id: subject_id
    )
    connection.email              = info["email"] || connection.email
    connection.access_token       = creds["token"]
    connection.refresh_token      = creds["refresh_token"] || connection.refresh_token
    connection.expires_at         = expiry_from_credentials(creds)
    # The current grant is the source of truth — the stored array reflects
    # the scope set actually attached to this access token, not a stale
    # historical union. The post-upsert partial-grant check (see #create)
    # uses this same list to detect missing required scopes.
    connection.scopes             = granted_scopes.uniq
    connection.needs_reauth       = false
    connection.last_authorized_at = Time.current

    connection.save!
    connection
  end

  # Return the subset of PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES that
  # did NOT make it onto this connection's stored scopes array. An
  # empty array means the grant covered everything pito needs; a
  # non-empty array means the user dismissed at least one scope on the
  # Google consent screen and the surface should prompt to reconnect.
  def missing_required_scopes(connection)
    required = Array(PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES)
    granted = Array(connection.scopes)
    required - granted
  end

  # Build the granted-scope list from the auth hash. OmniAuth
  # surfaces it under `extra.raw_info.scope` (space-joined string)
  # OR `credentials.scope` (also space-joined). Walk both spots.
  def parse_granted_scopes(extra, creds)
    raw = nil
    if extra.respond_to?(:[])
      raw_info = extra["raw_info"] || (extra.respond_to?(:raw_info) ? extra.raw_info : nil)
      raw = (raw_info && (raw_info["scope"] || raw_info[:scope])) ||
            extra["scope"]
    end
    raw ||= creds["scope"] if creds.respond_to?(:[])
    raw.to_s.split.reject(&:blank?)
  end

  # Google returns `expires_at` (Unix epoch). Some flows return
  # `expires_in` instead. Prefer `expires_at`; fall back to
  # `expires_in` plus now.
  def expiry_from_credentials(creds)
    if (epoch = creds["expires_at"]).present?
      Time.at(epoch.to_i).utc
    elsif (in_seconds = creds["expires_in"]).present?
      in_seconds.to_i.seconds.from_now
    else
      1.hour.from_now
    end
  end

  def failure_message(error)
    return "auth_failed" if error.nil?

    case error
    when ::OAuth2::Error then "auth_failed"
    else error.try(:message) || error.try(:type) || "auth_failed"
    end
  end

  def omniauth_failure_reason(error)
    return "missing_auth_hash" if error.nil?

    error.try(:type) || error.class.name
  end

  # Enumerate `mine: true` channels for the just-authorized connection
  # and add any that are not already linked. Returns a stable Hash
  # shape used by `compose_callback_flash`:
  #
  #   { added: [titles…], duplicates: [titles…], error: nil | "quota exceeded" | … }
  #
  # Duplicate detection is keyed on `youtube_channel_id` (the UC id,
  # e.g. "UCxxxxxx") — the unique index on `channels.youtube_channel_id`
  # is the source of truth. A duplicate match pointing at a different
  # connection is still treated as duplicate (no silent re-attachment).
  #
  # Errors from the YouTube client (quota, transient, needs reauth) are
  # caught here so the OAuth-success redirect still completes.
  def discover_and_link_channels(connection)
    items = []
    begin
      response = Channel::Youtube::Client.new(connection).channels_list(
        mine: true, parts: %i[snippet statistics]
      )
      items = Array(response[:items])
    rescue Channel::Youtube::QuotaExhaustedError
      audit("youtube_connection.callback.discovery_failed",
            connection_id: connection.id, reason: "quota_exhausted")
      return { added: [], duplicates: [], error: t("pito.youtube_connections.callback.errors.quota_exceeded") }
    rescue Channel::Youtube::NeedsReauthError
      audit("youtube_connection.callback.discovery_failed",
            connection_id: connection.id, reason: "needs_reauth")
      return { added: [], duplicates: [], error: t("pito.youtube_connections.callback.errors.needs_reauth") }
    rescue Channel::Youtube::TransientError
      audit("youtube_connection.callback.discovery_failed",
            connection_id: connection.id, reason: "transient")
      return { added: [], duplicates: [], error: t("pito.youtube_connections.callback.errors.transient") }
    end

    added = []
    duplicates = []

    items.each do |item|
      uc_id = item[:id].to_s
      next if uc_id.blank?

      title  = item.dig(:snippet, :title).to_s.presence
      handle = item.dig(:snippet, :custom_url).to_s.presence

      if Channel.exists?(youtube_channel_id: uc_id)
        duplicates << { title: title || uc_id, handle: handle }
        next
      end

      Channel.create!(
        youtube_channel_id:     uc_id,
        title:                  title,
        handle:                 handle,
        youtube_connection_id:  connection.id,
        last_synced_at:         Time.current
      )
      added << { title: title || uc_id, handle: handle }
    end

    audit("youtube_connection.callback.discovery_succeeded",
          connection_id: connection.id,
          added_count: added.length,
          duplicate_count: duplicates.length)
    { added: added, duplicates: duplicates, error: nil }
  end

  def compose_callback_flash(discovery)
    ns = "pito.youtube_connections.callback"

    if discovery[:error].present?
      return t("#{ns}.channel_lookup_error", error: discovery[:error])
    end

    added      = Array(discovery[:added])
    duplicates = Array(discovery[:duplicates])

    if added.empty? && duplicates.empty?
      return t("#{ns}.no_channels")
    end

    parts = []

    if added.any?
      if added.length == 1
        ch = added.first
        title  = ch.is_a?(Hash) ? ch[:title]  : ch
        handle = ch.is_a?(Hash) ? ch[:handle] : nil
        main = t("#{ns}.channel_connected",
                 title:  title,
                 handle: handle || "no-handle")
        extra = Pito::Copy.render("pito.copy.youtube.connected_extras")
        art   = Pito::Copy.render("pito.copy.youtube.ascii_art")
        parts << [ main, extra, art ].compact.join("<br>").html_safe
      else
        titles = added.map { |ch| ch.is_a?(Hash) ? ch[:title] : ch }.join(", ")
        parts << t("#{ns}.channels_added", count: added.length, titles: titles)
      end
    end

    if duplicates.length == 1
      ch = duplicates.first
      title = ch.is_a?(Hash) ? ch[:title] : ch
      handle = ch.is_a?(Hash) ? ch[:handle] : nil
      main  = t("#{ns}.already_linked.one",
                title:  title,
                handle: handle || "no-handle")
      art   = Pito::Copy.render("pito.copy.youtube.ascii_art")
      parts << [ main, art ].compact.join("<br>").html_safe
    end

    parts.join(" ")
  end

  # Audit trail for callback outcomes. One structured JSON
  # line per event via the AUTH_AUDIT_LOGGER, gated on the logger being
  # defined.
  def audit(event, **payload)
    return unless defined?(AUTH_AUDIT_LOGGER)

    AUTH_AUDIT_LOGGER.info({
      ts: Time.now.utc.iso8601(3),
      event: event
    }.merge(payload).to_json)
  rescue StandardError
    nil
  end
end
