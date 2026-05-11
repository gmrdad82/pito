require "rails_helper"

RSpec.describe "Settings::Security::Attempts", type: :request do
  include ActiveSupport::Testing::TimeHelpers


  describe "GET /settings/security/attempts" do
    let!(:older_failed) { travel_to(2.hours.ago) { create(:login_attempt) } }
    let!(:recent_success) { create(:login_attempt, :success) }
    let!(:blocked_row) { create(:login_attempt, :blocked, ip: "9.8.7.6", ip_prefix: "9.8.7.0/24") }

    it "renders the list sorted desc by created_at" do
      get settings_security_attempts_path
      expect(response).to have_http_status(:ok)
      # Newest comes first in the response body.
      body = response.body
      expect(body.index(blocked_row.fingerprint_short)).to be < body.index(older_failed.fingerprint_short)
    end

    it "filters by result=failed" do
      get settings_security_attempts_path, params: { result: "failed" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(older_failed.fingerprint_short)
      expect(response.body).not_to include(recent_success.fingerprint_short)
      expect(response.body).not_to include(blocked_row.fingerprint_short)
    end

    it "filters by ip exact match" do
      get settings_security_attempts_path, params: { ip: "9.8.7.6" }
      expect(response.body).to include(blocked_row.fingerprint_short)
      expect(response.body).not_to include(recent_success.fingerprint_short)
    end

    it "filters by fingerprint exact match" do
      get settings_security_attempts_path, params: { fingerprint: blocked_row.fingerprint_hash }
      expect(response.body).to include(blocked_row.fingerprint_short)
      expect(response.body).not_to include(recent_success.fingerprint_short)
    end

    it "filters by since" do
      get settings_security_attempts_path, params: { since: 1.hour.ago.iso8601 }
      expect(response.body).not_to include(older_failed.fingerprint_short)
      expect(response.body).to include(recent_success.fingerprint_short)
    end

    it "silently ignores invalid since timestamps" do
      get settings_security_attempts_path, params: { since: "garbage" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(recent_success.fingerprint_short)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get settings_security_attempts_path
      expect(response).to have_http_status(:found)
    end

    it "responds to the JSON branch with yes/no Booleans on rows" do
      get settings_security_attempts_path(format: :json)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["attempts"]).to be_an(Array)
      body["attempts"].each do |row|
        expect(%w[yes no]).to include(row["is_success"])
        expect(%w[yes no]).to include(row["is_failed"])
        expect(%w[yes no]).to include(row["is_blocked"])
      end
      expect(body["pagination"]).to include("page" => 1, "per_page" => 50)
    end

    it "shows 'no attempts match' when the filter is empty" do
      LoginAttempt.delete_all
      get settings_security_attempts_path
      expect(response.body).to include("no attempts match")
    end
  end

  describe "GET /settings/security/attempts/:id" do
    let(:attempt) { create(:login_attempt, :with_geo) }

    it "renders the detail page" do
      get settings_security_attempt_path(attempt)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(attempt.fingerprint_hash)
      expect(response.body).to include("Bucharest")
    end

    it "JSON returns yes/no Booleans" do
      get settings_security_attempt_path(attempt, format: :json)
      data = JSON.parse(response.body)
      expect(%w[yes no]).to include(data["is_success"])
      expect(%w[yes no]).to include(data["is_failed"])
      expect(%w[yes no]).to include(data["is_blocked"])
    end

    it "404s on an unknown id" do
      get settings_security_attempt_path(id: 999_999)
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get settings_security_attempt_path(attempt)
      expect(response).to have_http_status(:found)
    end
  end
end
