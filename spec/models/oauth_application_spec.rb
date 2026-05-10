require "rails_helper"

# Phase 8 — tenant drop. OauthApplication is now a thin Doorkeeper
# subclass with no extra scoping.
RSpec.describe OauthApplication, type: :model do
  describe "validations" do
    it "requires a name" do
      app = build(:oauth_application, name: nil)
      expect(app).not_to be_valid
    end

    it "requires a redirect_uri" do
      app = build(:oauth_application, redirect_uri: nil)
      expect(app).not_to be_valid
    end

    it "rejects scopes outside the configured catalog" do
      app = build(:oauth_application, scopes: "fake:scope")
      expect(app).not_to be_valid
    end
  end

  describe "secret generation" do
    it "generates a uid and a secret" do
      app = create(:oauth_application)
      expect(app.uid).to be_present
      expect(app.secret).to be_present
    end
  end

  describe "Phase 8 — no tenant association" do
    it "does not declare a tenant association" do
      expect(OauthApplication.reflect_on_association(:tenant)).to be_nil
    end
  end
end
