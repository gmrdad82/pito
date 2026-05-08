require "rails_helper"

RSpec.describe OauthApplication, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
  end

  describe "validations" do
    it "requires a name" do
      app = build(:oauth_application, name: nil)
      expect(app).not_to be_valid
    end

    it "requires a tenant" do
      app = build(:oauth_application, tenant: nil)
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
end
