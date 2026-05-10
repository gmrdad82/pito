require "rails_helper"

# Phase 8 — tenant drop. The denormalize_tenant_from_application
# callback is gone; the model is a thin Doorkeeper subclass with a
# `user` reader that resolves `resource_owner_id` to a User.
RSpec.describe OauthAccessToken, type: :model do
  let!(:application) { create(:oauth_application) }
  let!(:user) { Current.user || create(:user) }

  describe "Phase 8 — tenant plumbing removed" do
    it "no longer declares a tenant association" do
      expect(OauthAccessToken.reflect_on_association(:tenant)).to be_nil
    end

    it "no longer responds to denormalize_tenant_from_application" do
      token = OauthAccessToken.new
      expect(token.respond_to?(:denormalize_tenant_from_application, true)).to be(false)
    end
  end

  describe "#user" do
    it "resolves resource_owner_id to a User" do
      token = OauthAccessToken.create!(
        application: application,
        resource_owner_id: user.id,
        scopes: Scopes::DEV_READ,
        expires_in: 7200
      )
      expect(token.user).to eq(user)
    end

    it "returns nil when resource_owner_id is blank" do
      token = OauthAccessToken.new(application: application)
      expect(token.user).to be_nil
    end

    it "returns nil when the resource owner row has been deleted" do
      token = OauthAccessToken.create!(
        application: application,
        resource_owner_id: user.id,
        scopes: Scopes::DEV_READ,
        expires_in: 7200
      )
      user.destroy
      expect(token.user).to be_nil
    end
  end
end
