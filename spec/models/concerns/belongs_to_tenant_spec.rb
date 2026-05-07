require "rails_helper"

# Phase 5A §5.4 — `BelongsToTenant` default-scope behavior. Locked
# decision: when `Current.tenant_id` is nil, every query against a
# tenanted model raises `BelongsToTenant::TenantContextMissing`. Bugs
# should be loud, not silent.
RSpec.describe BelongsToTenant, type: :model do
  describe "default scope keyed on Current.tenant_id" do
    let!(:tenant_a) { Tenant.first || create(:tenant, slug: "alpha") }
    let!(:channel_a) do
      Current.tenant = tenant_a
      create(:channel, tenant: tenant_a)
    end

    it "filters by Current.tenant_id when Current.tenant is set" do
      Current.tenant = tenant_a
      expect(Channel.count).to eq(1)
      expect(Channel.first).to eq(channel_a)
    end

    it "raises TenantContextMissing when Current.tenant is nil" do
      Current.reset
      expect { Channel.count }.to raise_error(BelongsToTenant::TenantContextMissing)
      expect { Channel.first }.to raise_error(BelongsToTenant::TenantContextMissing)
      expect { Channel.where(channel_url: "...") }.to raise_error(BelongsToTenant::TenantContextMissing)
    end

    it "lets Model.unscoped bypass the scope explicitly" do
      Current.reset
      expect { Channel.unscoped.count }.not_to raise_error
      expect(Channel.unscoped.count).to be >= 1
    end
  end

  describe "tenant_id presence validation" do
    it "rejects a Channel without a tenant_id even with the default scope stamping" do
      Current.reset
      ch = Channel.unscoped.new(channel_url: "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
      expect(ch).not_to be_valid
      expect(ch.errors[:tenant_id]).to include("can't be blank")
    end
  end

  describe "models that include the concern" do
    [
      Channel, Video, Playlist, PlaylistItem, VideoStat, VideoUpload,
      SavedView, BulkOperation, BulkOperationItem,
      Project, Collection, Game, Footage, Note, Timeline, ProjectReference
    ].each do |klass|
      it "#{klass.name} includes BelongsToTenant" do
        expect(klass.included_modules).to include(BelongsToTenant)
      end
    end

    it "Tenant does NOT include BelongsToTenant (it has no tenant_id)" do
      expect(Tenant.included_modules).not_to include(BelongsToTenant)
    end

    it "User does NOT include BelongsToTenant (login flows query before Current is set)" do
      expect(User.included_modules).not_to include(BelongsToTenant)
    end
  end
end
