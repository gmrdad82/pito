require "rails_helper"

RSpec.describe ProjectReference, type: :model do
  describe "associations" do
    subject { build(:project_reference) }
    # Phase 5A — `belong_to(:tenant)` was a `required: true` shoulda
    # check, but the `before_validation :denormalize_tenant_from_project`
    # callback fills `tenant_id` from `project` whenever it is missing,
    # so the matcher's "set tenant to nil and expect invalid" probe
    # never sees nil after validation runs. Assert the declarations
    # explicitly instead.
    it "declares belongs_to :tenant via the BelongsToTenant concern" do
      reflection = ProjectReference.reflect_on_association(:tenant)
      expect(reflection).not_to be_nil
      expect(reflection.macro).to eq(:belongs_to)
    end

    it "validates tenant_id presence" do
      ref = ProjectReference.unscoped.new
      ref.tenant_id = nil
      ref.valid?
      expect(ref.errors[:tenant_id]).to include("can't be blank")
    end

    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:referenceable) }
  end

  describe "validations" do
    let(:tenant) { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }

    # Phase 5A — re-pin Current.tenant onto the explicit `tenant`
    # let so default-scoped validators (e.g. uniqueness queries)
    # see the right rows.
    before { Current.tenant = tenant }

    it "accepts a Game referenceable" do
      game = create(:game, tenant: tenant)
      ref = ProjectReference.new(project: project, tenant: tenant, referenceable: game)
      expect(ref).to be_valid
    end

    it "accepts a Collection referenceable" do
      collection = create(:collection, tenant: tenant)
      ref = ProjectReference.new(project: project, tenant: tenant, referenceable: collection)
      expect(ref).to be_valid
    end

    it "rejects unknown referenceable_type" do
      ref = ProjectReference.new(project: project, tenant: tenant,
                                 referenceable_type: "Channel", referenceable_id: 1)
      expect(ref).not_to be_valid
      expect(ref.errors[:referenceable_type]).to be_present
    end

    it "rejects cross-tenant references" do
      other_tenant = create(:tenant)
      foreign_game = create(:game, tenant: other_tenant)
      ref = ProjectReference.new(project: project, tenant: tenant, referenceable: foreign_game)
      expect(ref).not_to be_valid
      expect(ref.errors[:referenceable]).to include(/same tenant/)
    end

    it "enforces uniqueness per project + referenceable_type + referenceable_id" do
      game = create(:game, tenant: tenant)
      ProjectReference.create!(project: project, tenant: tenant, referenceable: game)

      dup = ProjectReference.new(project: project, tenant: tenant, referenceable: game)
      expect(dup).not_to be_valid
    end

    it "permits the same referenceable across different projects" do
      other_project = create(:project, tenant: tenant)
      game = create(:game, tenant: tenant)
      ProjectReference.create!(project: project, tenant: tenant, referenceable: game)

      second = ProjectReference.new(project: other_project, tenant: tenant, referenceable: game)
      expect(second).to be_valid
    end
  end

  describe "tenant denormalization (before_validation)" do
    let(:tenant) { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }

    # Phase 5A — re-pin Current.tenant onto the explicit `tenant`
    # let so default-scoped queries (e.g. find_by!) see the rows
    # this block builds.
    before { Current.tenant = tenant }

    it "fills tenant_id from project on Project#games <<" do
      game = create(:game, tenant: tenant)
      expect { project.games << game }.not_to raise_error
      ref = ProjectReference.find_by!(project: project, referenceable: game)
      expect(ref.tenant_id).to eq(project.tenant_id)
    end

    it "preserves an explicitly assigned tenant_id (||= semantics)" do
      game = create(:game, tenant: tenant)
      ref = ProjectReference.new(project: project, referenceable: game, tenant_id: tenant.id)
      expect(ref).to be_valid
      expect(ref.tenant_id).to eq(tenant.id)
    end

    it "still rejects a tenant_id that disagrees with the project's tenant" do
      other_tenant = create(:tenant)
      game = create(:game, tenant: tenant)
      ref = ProjectReference.new(
        project: project, referenceable: game, tenant_id: other_tenant.id
      )
      # The cross-tenant guard fires on the referenceable side; the explicit
      # tenant_id is honoured but the row still fails to save because the
      # referenceable doesn't belong to that tenant.
      expect(ref).not_to be_valid
    end
  end
end
