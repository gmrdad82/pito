# Phase 12 — Step B (6b-doorkeeper-oauth-server.md) — OAuth application
# admin UI.
#
# Mirrors the `/settings/tokens` flow: index lists applications, `new`
# renders the form, `create` shows the secrets-once page, `show` is the
# read-only detail view, `destroy` revokes (cascades to all active
# tokens via Doorkeeper's `revoke_all_for` helper). All forms post
# through standard CSRF; the destroy goes through the action-screen
# framework via the `revoke` GET (no `data-turbo-confirm`).
#
# Phase 8 — tenant drop. Applications are install-wide; no
# `where(tenant_id: ...)` scoping.
class Settings::OauthApplicationsController < ApplicationController
  before_action :load_application, only: %i[show destroy revoke]

  def index
    @applications = OauthApplication.order(created_at: :desc)
  end

  def new
    @application = OauthApplication.new(
      confidential: false,
      scopes: ""
    )
  end

  def create
    name           = params.dig(:oauth_application, :name).to_s.strip
    redirect_uri   = params.dig(:oauth_application, :redirect_uri).to_s.strip
    raw_scopes     = Array(params.dig(:oauth_application, :scopes)).reject(&:blank?)
    confidential   = params.dig(:oauth_application, :confidential).to_s == "yes"

    invalid = raw_scopes - Scopes::ALL
    if invalid.any?
      @application = OauthApplication.new(
        name: name,
        redirect_uri: redirect_uri,
        scopes: raw_scopes.join(" "),
        confidential: confidential
      )
      @application.errors.add(:scopes, "contains invalid entries: #{invalid.join(', ')}")
      render :new, status: :unprocessable_content
      return
    end

    @application = OauthApplication.new(
      name: name,
      redirect_uri: redirect_uri,
      scopes: raw_scopes.join(" "),
      confidential: confidential
    )

    if @application.save
      @plaintext_uid    = @application.uid
      @plaintext_secret = @application.plaintext_secret || @application.secret
      render :create
    else
      render :new, status: :unprocessable_content
    end
  end

  # GET /settings/oauth_applications/:id/revoke — action confirmation screen.
  def revoke
  end

  def show
    @active_tokens  = OauthAccessToken.where(application_id: @application.id, revoked_at: nil).order(created_at: :desc)
    @revoked_tokens = OauthAccessToken.where(application_id: @application.id).where.not(revoked_at: nil).order(revoked_at: :desc).limit(20)
  end

  def destroy
    OauthAccessToken.where(application_id: @application.id, revoked_at: nil).update_all(revoked_at: Time.current)
    OauthAccessGrant.where(application_id: @application.id, revoked_at: nil).update_all(revoked_at: Time.current)

    @application.destroy

    audit_destroy(@application)

    redirect_to settings_oauth_applications_path, notice: "application revoked and all its tokens were revoked."
  end

  private

  def load_application
    @application = OauthApplication.find(params[:id])
  end

  def audit_destroy(application)
    return unless defined?(AUTH_AUDIT_LOGGER)

    AUTH_AUDIT_LOGGER.info({
      ts: Time.now.utc.iso8601(3),
      event: "oauth.application.destroyed",
      application_id: application.id,
      application_name: application.name,
      user_id: Current.user&.id
    }.to_json)
  rescue StandardError
    nil
  end
end
