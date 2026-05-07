require "rails_helper"

# Phase 5A §5.5 — cross-tenant leak spec.
#
# Two-tenant fixture: factory creates `tenant_a` and `tenant_b` with one
# user each and one of every data-holding model in each tenant. Then:
#
#   1. With `Current.tenant = tenant_a`, every tenanted model has count=1
#      and the row belongs to `tenant_a`.
#   2. `Model.find(<tenant_b row id>)` raises `RecordNotFound` (the
#      default scope filters it before find).
#   3. Switch to `tenant_b`, repeat.
#   4. With `Current.reset`, every tenanted model query raises
#      `BelongsToTenant::TenantContextMissing`.
#
# The list of tenanted models is the canonical Phase 5A set (§5.4).
# `McpAccessToken` / `ApiToken` is owned by 5B; this spec does not
# assert on it directly to stay within 5A's scope.
RSpec.describe "cross-tenant leak prevention", type: :model do
  TENANTED_MODELS = [
    Channel, Video, Playlist, PlaylistItem, VideoStat, VideoUpload,
    SavedView, BulkOperation, BulkOperationItem,
    Project, Collection, Game, Footage, Note, Timeline, ProjectReference
  ].freeze

  # Build one row per tenanted model under the given tenant. The build
  # order matches the FK dependency graph (Channel before Video, Project
  # before Note, etc). Each row uses the tenant explicitly so the
  # `BelongsToTenant` default-scope stamp never crosses tenants.
  #
  # The `bulk_operation_item` build is intentionally pinned to the
  # already-created channel + video so we end up with exactly one
  # Channel and one Video per tenant — the count assertions below
  # rely on that.
  def seed_full_world_under(tenant)
    Current.tenant = tenant

    channel = create(:channel, tenant: tenant)
    video   = create(:video, channel: channel, tenant: tenant)
    playlist = create(:playlist, channel: channel, tenant: tenant)
    playlist_item = create(:playlist_item, playlist: playlist, video: video, tenant: tenant)
    video_stat = create(:video_stat, video: video, tenant: tenant, date: Date.current)
    video_upload = create(:video_upload, channel: channel, tenant: tenant)
    saved_view = create(:saved_view, tenant: tenant)
    bulk_op = create(:bulk_operation, tenant: tenant)
    # Reuse the existing video so we don't create a second channel/video
    # under this tenant.
    bulk_op_item = create(
      :bulk_operation_item,
      bulk_operation: bulk_op, tenant: tenant,
      video: video, target: video
    )

    project    = create(:project, tenant: tenant)
    collection = create(:collection, tenant: tenant)
    game       = create(:game, tenant: tenant, collection: collection)
    footage    = create(:footage, project: project, tenant: tenant)
    note       = create(:note, project: project, tenant: tenant)
    timeline   = create(:timeline, project: project, tenant: tenant)
    project_ref = create(:project_reference, project: project, referenceable: game, tenant: tenant)

    {
      Channel => channel, Video => video, Playlist => playlist,
      PlaylistItem => playlist_item, VideoStat => video_stat,
      VideoUpload => video_upload, SavedView => saved_view,
      BulkOperation => bulk_op, BulkOperationItem => bulk_op_item,
      Project => project, Collection => collection, Game => game,
      Footage => footage, Note => note, Timeline => timeline,
      ProjectReference => project_ref
    }
  end

  let!(:tenant_a) { create(:tenant, name: "Alpha", slug: "alpha-#{SecureRandom.hex(2)}") }
  let!(:tenant_b) { create(:tenant, name: "Beta",  slug: "beta-#{SecureRandom.hex(2)}") }

  let!(:rows_a) { seed_full_world_under(tenant_a) }
  let!(:rows_b) { seed_full_world_under(tenant_b) }

  describe "with Current.tenant = tenant_a" do
    before { Current.tenant = tenant_a }

    TENANTED_MODELS.each do |model|
      it "#{model.name} returns only the tenant_a row" do
        expect(model.count).to eq(1)
        expect(model.first.tenant_id).to eq(tenant_a.id)
      end

      it "#{model.name}.find on a tenant_b id raises RecordNotFound" do
        b_row = rows_b.fetch(model)
        expect { model.find(b_row.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "with Current.tenant = tenant_b (symmetry)" do
    before { Current.tenant = tenant_b }

    TENANTED_MODELS.each do |model|
      it "#{model.name} returns only the tenant_b row" do
        expect(model.count).to eq(1)
        expect(model.first.tenant_id).to eq(tenant_b.id)
      end

      it "#{model.name}.find on a tenant_a id raises RecordNotFound" do
        a_row = rows_a.fetch(model)
        expect { model.find(a_row.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "with Current.reset (no tenant context)" do
    before { Current.reset }

    TENANTED_MODELS.each do |model|
      it "#{model.name}.count raises TenantContextMissing" do
        expect { model.count }.to raise_error(BelongsToTenant::TenantContextMissing)
      end
    end
  end

  describe "Model.unscoped escape hatch" do
    before { Current.reset }

    it "lets Channel.unscoped see rows from both tenants" do
      expect(Channel.unscoped.count).to eq(2)
      expect(Channel.unscoped.pluck(:tenant_id)).to contain_exactly(tenant_a.id, tenant_b.id)
    end
  end
end
