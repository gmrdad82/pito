require "rails_helper"

# Phase 12 — Step A (6a-sessions-and-login-ui.md). Cookie-session auth
# replaced the implicit `before_action :set_current_tenant_and_user`
# pin. After a successful auth the controller pins
# `Current.session / .user` from the resolved row; without
# a session cookie HTML routes redirect to /login.
#
# Phase 8 — tenant drop. `Current.tenant` is gone.
RSpec.describe "ApplicationController Current population", type: :request do
  describe "with a valid session cookie" do
    let!(:user) { Current.user || create(:user) }

    it "responds 200 to / when signed in" do
      sign_in_as(user)
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "without a session cookie", :unauthenticated do
    it "redirects HTML routes to /login" do
      get root_path
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(login_path)
    end

    it "preserves the intended URL via a signed cookie" do
      get channels_path
      expect(response).to redirect_to(login_path)
      set_cookie_header = Array(response.headers["Set-Cookie"]).flatten.join("\n")
      expect(set_cookie_header).to include(Sessions::AuthConcern::INTENDED_URL_COOKIE.to_s)
    end
  end

  describe "Current attributes after Phase 8" do
    it "no longer declares :tenant" do
      expect(Current.respond_to?(:tenant)).to be(false)
    end

    it "still declares :user, :token, :session" do
      expect(Current.respond_to?(:user)).to be(true)
      expect(Current.respond_to?(:token)).to be(true)
      expect(Current.respond_to?(:session)).to be(true)
    end
  end
end
