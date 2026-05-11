require "rails_helper"

RSpec.describe "Settings::Security::Attempts::Purges", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  describe "GET /settings/security/attempts/purge" do
    let!(:failed)  { create(:login_attempt) }
    let!(:success) { create(:login_attempt, :success) }

    it "renders the preview screen with no filter" do
      get settings_security_attempts_purge_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("enter at least one filter")
    end

    it "renders the preview count when a filter narrows the set" do
      get settings_security_attempts_purge_path, params: { result: "failed" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("will hard-delete")
      expect(response.body).to include("<strong>1</strong>")
    end

    it "surfaces an alert on invalid timestamp" do
      get settings_security_attempts_purge_path, params: { since: "garbage" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("invalid")
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get settings_security_attempts_purge_path
      expect(response).to have_http_status(:found)
    end
  end

  describe "POST /settings/security/attempts/purge" do
    let!(:failed)  { create(:login_attempt) }
    let!(:success) { create(:login_attempt, :success) }

    it "hard-deletes matching rows when confirm=yes" do
      post settings_security_attempts_purge_path,
           params: { result: "failed", confirm: "yes" }

      expect(response).to redirect_to(settings_security_attempts_path)
      expect(flash[:notice]).to match(/purged 1 attempt/)
      expect(LoginAttempt.find_by(id: failed.id)).to be_nil
      expect(LoginAttempt.find_by(id: success.id)).to be_present
    end

    it "redirects with alert when no filter supplied" do
      post settings_security_attempts_purge_path, params: { confirm: "yes" }

      expect(response).to redirect_to(settings_security_attempts_purge_path)
      expect(flash[:alert]).to match(/at least one filter/)
      expect(LoginAttempt.count).to eq(2)
    end

    it "treats confirm!=yes as cancel" do
      post settings_security_attempts_purge_path,
           params: { result: "failed", confirm: "no" }

      expect(response).to redirect_to(settings_security_attempts_path)
      expect(flash[:alert]).to match(/cancelled/)
      expect(LoginAttempt.count).to eq(2)
    end

    it "redirects with alert on invalid timestamp" do
      post settings_security_attempts_purge_path,
           params: { since: "garbage", confirm: "yes" }

      expect(response).to redirect_to(settings_security_attempts_purge_path)
      expect(flash[:alert]).to match(/invalid/)
      expect(LoginAttempt.count).to eq(2)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      post settings_security_attempts_purge_path,
           params: { result: "failed", confirm: "yes" }
      expect(response).to have_http_status(:found)
    end
  end
end
