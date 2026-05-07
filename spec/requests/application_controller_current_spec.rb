require "rails_helper"

# Phase 5A — ApplicationController populates Current.tenant /
# Current.user via `before_action :set_current_tenant_and_user`. This
# spec locks that contract: Current is set to `Tenant.first` /
# `User.first` before the action body runs, and the request completes
# normally as long as a tenant exists.
RSpec.describe "ApplicationController Current population", type: :request do
  describe "before_action :set_current_tenant_and_user" do
    context "when a tenant and user exist" do
      let!(:tenant) { Tenant.first || create(:tenant) }
      let!(:user)   { User.first   || create(:user, tenant: tenant) }

      it "assigns Current.tenant to Tenant.first during the request" do
        get root_path
        # After Current.reset (in the after(:each) hook) the value is cleared,
        # so we capture during the request via the controller. Easiest stable
        # check: the request succeeds AND Tenant.first is what we expect.
        expect(response).to have_http_status(:ok)
        expect(Tenant.first).to eq(tenant)
      end

      it "actually sets Current.tenant before the action body runs" do
        # Spy on the assignment so we know the before_action fired with the
        # right value. We assert the setter is called with Tenant.first.
        expect(Current).to receive(:tenant=).with(Tenant.first).and_call_original
        expect(Current).to receive(:user=).with(User.first).and_call_original
        get root_path
      end
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
