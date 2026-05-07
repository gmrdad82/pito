# Phase 3 — Step C (5c-settings-ui-and-docs.md) — Settings UI for token CRUD.
#
# Mirrors the rake task surface (`bin/rails tokens:create / tokens:list /
# tokens:revoke`) at the web layer. Plaintext is shown exactly once on the
# `create` success page; subsequent visits to the index never re-display the
# plaintext (only `last_token_preview`, the last 4 chars).
#
# Revoke is a soft-delete: `revoked_at = Time.current`. The row stays in the
# database forever for audit trail. The action confirmation flow is rendered
# inline (a dedicated GET to /settings/tokens/:id/revoke shows the action
# screen, POST commits) — matching the project's "no JS confirms" rule.
#
# Auth: this controller lives behind the implicit single-user session
# (`Current.user = User.first` from `ApplicationController`). HTML routes do
# NOT require bearer tokens in this phase — Phase 6 lands proper login. For
# now, anyone reaching the host can mint tokens; that's acceptable because
# the host is bound to 127.0.0.1 + cloudflared.
class Settings::TokensController < ApplicationController
  def index
    scope = ApiToken.where(tenant_id: Current.tenant_id)
    @active_tokens = scope.active.order(created_at: :desc)
    @revoked_tokens = scope.revoked.order(revoked_at: :desc)
  end

  def new
    @token = ApiToken.new(scopes: [])
  end

  def create
    name = params.dig(:token, :name).to_s.strip
    raw_scopes = Array(params.dig(:token, :scopes)).reject(&:blank?)
    expires_at_param = params.dig(:token, :expires_at).to_s.strip.presence

    expires_at = nil
    if expires_at_param
      begin
        expires_at = Date.parse(expires_at_param).end_of_day
      rescue ArgumentError
        @token = ApiToken.new(name: name, scopes: raw_scopes)
        @token.errors.add(:expires_at, "is not a valid date")
        render :new, status: :unprocessable_entity
        return
      end
    end

    invalid = raw_scopes - Scopes::ALL
    if invalid.any?
      @token = ApiToken.new(name: name, scopes: raw_scopes)
      @token.errors.add(:scopes, "contains invalid entries: #{invalid.join(", ")}")
      render :new, status: :unprocessable_content
      return
    end

    if name.blank?
      @token = ApiToken.new(name: name, scopes: raw_scopes)
      @token.errors.add(:name, "can't be blank")
      render :new, status: :unprocessable_content
      return
    end

    if raw_scopes.empty?
      @token = ApiToken.new(name: name, scopes: raw_scopes)
      @token.errors.add(:scopes, "must include at least one scope")
      render :new, status: :unprocessable_content
      return
    end

    @token, @plaintext = ApiToken.generate!(
      tenant: Current.tenant,
      user: Current.user,
      name: name,
      scopes: raw_scopes,
      expires_at: expires_at
    )

    AUTH_AUDIT_LOGGER.info({ event: "token.created", token_id: @token.id, name: @token.name, scopes: @token.scopes }.to_json) if defined?(AUTH_AUDIT_LOGGER)

    render :create
  rescue ActiveRecord::RecordInvalid => e
    @token = e.record
    render :new, status: :unprocessable_content
  end

  # GET /settings/tokens/:id/revoke — action confirmation screen (same shape
  # as /deletions/:type/:ids). Lists what the action will do; submitting POSTs
  # back to destroy.
  def revoke
    @token = ApiToken.where(tenant_id: Current.tenant_id).find(params[:id])
  end

  def destroy
    @token = ApiToken.where(tenant_id: Current.tenant_id).find(params[:id])
    if @token.revoked?
      redirect_to settings_tokens_path, alert: "token already revoked."
      return
    end

    @token.revoke!
    AUTH_AUDIT_LOGGER.info({ event: "token.revoked", token_id: @token.id, name: @token.name }.to_json) if defined?(AUTH_AUDIT_LOGGER)

    redirect_to settings_tokens_path, notice: "token revoked."
  end
end
