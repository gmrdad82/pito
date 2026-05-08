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
