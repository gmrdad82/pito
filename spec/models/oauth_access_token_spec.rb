require "rails_helper"

RSpec.describe OauthAccessToken, type: :model do
  let!(:application) { create(:oauth_application) }
  let!(:user) { Current.user || create(:user, tenant: Current.tenant) }

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
  end

  describe "denormalize_tenant_from_application" do
    it "copies the application's tenant_id onto the token before validation" do
      token = OauthAccessToken.new(
        application: application,
        resource_owner_id: user.id,
        scopes: Scopes::DEV_READ,
        expires_in: 7200
      )
      token.valid?
      expect(token.tenant_id).to eq(application.tenant_id)
    end

    it "persists tenant_id on creation" do
      token = OauthAccessToken.create!(
        application: application,
        resource_owner_id: user.id,
        scopes: Scopes::DEV_READ,
        expires_in: 7200
      )
      expect(token.reload.tenant_id).to eq(application.tenant_id)
    end
  end
end
