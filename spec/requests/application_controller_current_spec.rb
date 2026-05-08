require "rails_helper"

# Phase 12 — Step A (6a-sessions-and-login-ui.md). Cookie-session auth
# replaced the implicit `before_action :set_current_tenant_and_user`
# pin. After a successful auth the controller pins
# `Current.session / .user / .tenant` from the resolved row; without
# a session cookie HTML routes redirect to /login.
#
# Phase 5A's spec (Tenant.first / User.first being assigned) is no
# longer the contract — the auth concern owns the assignment.
RSpec.describe "ApplicationController Current population", type: :request do
  describe "with a valid session cookie" do
    let!(:user) { Current.user || create(:user, tenant: Current.tenant) }

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
      # The signed cookie is set on the response; subsequent followups
      # would read it back. Set-Cookie may be a single string or an
      # Array of strings depending on Rack version; flatten to a string
      # for the substring check.
      set_cookie_header = Array(response.headers["Set-Cookie"]).flatten.join("\n")
      expect(set_cookie_header).to include(Sessions::AuthConcern::INTENDED_URL_COOKIE.to_s)
    end
  end

  # Phase 5A — Current.reset hook + the spec/support/tenant_context
  # before(:each) work together: every example starts with Current
  # bound to a freshly-seeded default tenant (so factory creates and
  # tenanted-model queries Just Work), and the after(:each) wipes
  # state so nothing leaks into the next example.
  describe "Current lifecycle between specs" do
    it "is bound to a tenant at the top of an example via the test support hook" do
      expect(Current.tenant).not_to be_nil
    end
  end
end
