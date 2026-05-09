require "rails_helper"

RSpec.describe "Settings::OauthApplications", type: :request do
  let!(:user) { Current.user || create(:user, tenant: Current.tenant) }

  describe "GET /settings/oauth_applications" do
    it "lists applications for the current tenant" do
      sign_in_as(user)
      app = create(:oauth_application, tenant: Current.tenant, name: "vis-test")

      get settings_oauth_applications_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("vis-test")
      expect(response.body).to include(app.uid)
    end

    it "middle-truncates long redirect URIs and exposes the full value via title=" do
      sign_in_as(user)
      long_uri = "https://very-long-subdomain.example.com/api/auth/oauth_callback_endpoint"
      app = create(
        :oauth_application,
        tenant: Current.tenant,
        name: "truncate-test",
        redirect_uri: long_uri
      )

      get settings_oauth_applications_path
      expect(response).to have_http_status(:ok)

      # The cell title carries the full value for hover-reveal.
      expect(response.body).to include(%(title="#{long_uri}"))

      # The rendered cell contains a middle-truncated form
      # (`head…tail` with the U+2026 ellipsis), NOT the full URI.
      # Phase 7.5 — tightened to head/tail 12/12 so typical OAuth
      # callback URLs (e.g. https://claude.ai/api/mcp/auth_callback,
      # 38 chars) reliably trigger truncation rather than slipping
      # through the previous 40-char threshold.
      truncated = view_helper_middle_truncate(long_uri, head: 12, tail: 12)
      expect(truncated).not_to eq(long_uri)
      expect(response.body).to include(truncated)
    end

    it "middle-truncates the 43-char Doorkeeper-issued client_id and exposes the full value via title=" do
      sign_in_as(user)
      app = create(:oauth_application, tenant: Current.tenant, name: "uid-truncate-test")

      get settings_oauth_applications_path
      expect(response).to have_http_status(:ok)

      # The cell title carries the full uid for hover-reveal.
      expect(response.body).to include(%(title="#{app.uid}"))

      # The rendered cell contains a middle-truncated form
      # (head/tail 8/8) of the uid, NOT the full 43-char value.
      truncated = view_helper_middle_truncate(app.uid, head: 8, tail: 8)
      expect(truncated).not_to eq(app.uid)
      expect(response.body).to include(truncated)
    end

    # Inline helper bound to the same implementation as
    # `ApplicationHelper#middle_truncate`. Avoids dragging the helper
    # module into a request spec just to recompute the expected string.
    def view_helper_middle_truncate(str, head:, tail:)
      ellipsis = "…"
      return "" if str.to_s.empty?
      return str if str.length <= head + 1 + tail
      "#{str[0...head]}#{ellipsis}#{str[-tail..]}"
    end
  end

  describe "POST /settings/oauth_applications" do
    it "creates an application and renders the show-secrets-once page" do
      sign_in_as(user)
      expect {
        post settings_oauth_applications_path, params: {
          oauth_application: {
            name: "new-app",
            redirect_uri: "http://127.0.0.1:8765/callback",
            scopes: [ Scopes::DEV_READ, Scopes::PROJECT_READ ],
            confidential: "no"
          }
        }
      }.to change(OauthApplication, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("client_id")
      expect(response.body).to include("client_secret")
      created = OauthApplication.where(name: "new-app").first
      expect(created.uid).to be_present
      expect(response.body).to include(created.uid)

      # Phase 7.5 — `[copy]` affordance on credentials (Stimulus
      # `clipboard-copy` controller). Client_id, client_secret, and
      # mcp server URL all wear the bracketed copy link.
      expect(response.body.scan(/data-controller="clipboard-copy"/).length).to be >= 3
      expect(response.body).to include('data-action="click->clipboard-copy#copy"')
      expect(response.body).to include("[<span class=\"bl\">copy</span>]")

      # Phase 7.5 — MCP server URL row sourced from
      # `Pito::PublicHosts.mcp_base`. The value clients paste into
      # Claude.ai / Claude Desktop to reach the Pito MCP Puma.
      expect(response.body).to include("mcp server URL")
      expect(response.body).to include("#{Pito::PublicHosts.mcp_base}/mcp")
    end

    it "rejects an invalid scope" do
      sign_in_as(user)
      post settings_oauth_applications_path, params: {
        oauth_application: {
          name: "bad",
          redirect_uri: "http://127.0.0.1:8765/callback",
          scopes: [ "fake:scope" ],
          confidential: "no"
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /settings/oauth_applications/:id" do
    it "renders the read-only detail with a [copy] affordance on client_id" do
      sign_in_as(user)
      app = create(:oauth_application, tenant: Current.tenant)

      get settings_oauth_application_path(app)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(app.uid)
      # Phase 7.5 — `[copy]` affordance on `client_id`. `client_secret`
      # is intentionally absent (visible-once on the create page only).
      expect(response.body).to include('data-controller="clipboard-copy"')
      expect(response.body).to include('data-action="click->clipboard-copy#copy"')
      expect(response.body).not_to include("client_secret")

      # Phase 7.5 — MCP server URL row mirrored from the create-success
      # page so existing apps can re-find the URL after the secret has
      # been one-time-shown.
      expect(response.body).to include("mcp server URL")
      expect(response.body).to include("#{Pito::PublicHosts.mcp_base}/mcp")
    end
  end

  describe "GET /settings/oauth_applications/:id/revoke" do
    it "renders the action confirmation screen" do
      sign_in_as(user)
      app = create(:oauth_application, tenant: Current.tenant)

      get revoke_settings_oauth_application_path(app)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[revoke]")
    end
  end

  describe "DELETE /settings/oauth_applications/:id" do
    it "destroys the application and cascades to its tokens" do
      sign_in_as(user)
      app = create(:oauth_application, tenant: Current.tenant)
      token = OauthAccessToken.create!(
        application: app,
        resource_owner_id: user.id,
        scopes: Scopes::DEV_READ,
        expires_in: 7200
      )

      delete settings_oauth_application_path(app)
      expect(response).to redirect_to(settings_oauth_applications_path)
      expect(OauthApplication.unscoped.where(id: app.id)).to be_empty
      # Token is either revoked (controller's update_all) or destroyed
      # (Doorkeeper's cascade) — both leave the token unable to authenticate.
      reloaded = OauthAccessToken.unscoped.where(id: token.id).first
      expect(reloaded.nil? || reloaded.revoked_at.present?).to be true
    end
  end
end
