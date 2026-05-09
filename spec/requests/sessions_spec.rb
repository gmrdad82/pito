require "rails_helper"

# Phase 12 — Step A (6a-sessions-and-login-ui.md) — login / logout request
# spec.
RSpec.describe "Sessions", type: :request do
  let(:password) { "supersecret" }
  let!(:user) do
    User.where(tenant_id: Current.tenant.id).first ||
      create(:user, tenant: Current.tenant, password: password, password_confirmation: password)
  end

  before do
    # Reset the seed-time password so we can authenticate against a
    # known plaintext regardless of factory-supplied default.
    user.update!(password: password, password_confirmation: password)
  end

  describe "GET /login", :unauthenticated do
    it "renders the login form" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[log in]")
      expect(response.body).to include("name=\"identifier\"")
      expect(response.body).to include("email or username")
      expect(response.body).to include("name=\"password\"")
      expect(response.body).to include("name=\"remember_me\"")
    end

    it "does not render an inline duplicate of the flash error" do
      # The toast at app/views/shared/_flash_toasts.html.erb is the only
      # error surface; the form must NOT render a second .flash-error block.
      post login_path, params: { identifier: user.email, password: "wrong" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.scan(/invalid email or password/i).length).to eq(1)
      expect(response.body).not_to include("flash-error")
    end
  end

  describe "POST /login", :unauthenticated do
    it "creates a session, sets a signed cookie, and redirects on success" do
      expect {
        post login_path, params: { identifier: user.email, password: password }
      }.to change { Session.unscoped.where(user_id: user.id).count }.by(1)

      expect(response).to have_http_status(:found)
      expect(response.headers["Set-Cookie"].to_s).to include(Sessions::Authenticator::COOKIE_NAME.to_s)

      session_row = Session.unscoped.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be false
    end

    it "accepts a username as the identifier" do
      expect {
        post login_path, params: { identifier: user.username, password: password }
      }.to change { Session.unscoped.where(user_id: user.id).count }.by(1)
      expect(response).to have_http_status(:found)
    end

    it "is case-insensitive on the username identifier (citext)" do
      mixed = user.username.swapcase
      expect {
        post login_path, params: { identifier: mixed, password: password }
      }.to change { Session.unscoped.where(user_id: user.id).count }.by(1)
      expect(response).to have_http_status(:found)
    end

    it "is case-insensitive on the email identifier (citext)" do
      expect {
        post login_path, params: { identifier: user.email.upcase, password: password }
      }.to change { Session.unscoped.where(user_id: user.id).count }.by(1)
      expect(response).to have_http_status(:found)
    end

    it "renders the generic error and 422 on wrong password" do
      post login_path, params: { identifier: user.email, password: "not-it" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("invalid email or password")
    end

    it "renders the same generic error on unknown email" do
      post login_path, params: { identifier: "nobody@nowhere.test", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("invalid email or password")
    end

    it "renders the same generic error on unknown username" do
      post login_path, params: { identifier: "ghost", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("invalid email or password")
    end

    it "extends the cookie expires when remember_me=yes" do
      post login_path, params: { identifier: user.email, password: password, remember_me: "yes" }
      expect(response.headers["Set-Cookie"].to_s).to include("expires=")
      session_row = Session.unscoped.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be true
    end

    it "ignores remember_me when not set to the literal yes" do
      post login_path, params: { identifier: user.email, password: password, remember_me: "true" }
      session_row = Session.unscoped.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be false
    end

    it "throttles after 10 failures from the same IP" do
      11.times do
        post login_path, params: { identifier: user.email, password: "still-wrong" }
      end
      expect(response).to have_http_status(:too_many_requests)
    end

    it "redirects to the intended URL when one was stashed" do
      get channels_path
      # The unauthenticated request stashed `/channels` in the signed cookie.
      post login_path, params: { identifier: user.email, password: password }
      expect(response).to redirect_to(channels_path)
    end
  end

  describe "DELETE /session" do
    it "revokes the session row and clears the cookie" do
      session_row = sign_in_as(user)
      delete session_logout_path

      expect(response).to redirect_to(login_path)
      expect(session_row.reload.revoked?).to be true
      expect(response.headers["Set-Cookie"].to_s).to include("#{Sessions::Authenticator::COOKIE_NAME}=;")
    end
  end
end
