require "rails_helper"

# Phase 8 — tenant drop. ProjectReference no longer carries a tenant
# column or a cross-tenant guard. Project + Game / Project + Collection
# are install-wide associations.
RSpec.describe ProjectReference, type: :model do
  describe "associations" do
    subject { build(:project_reference) }

    it "does not declare a tenant association" do
      expect(ProjectReference.reflect_on_association(:tenant)).to be_nil
    end

    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:referenceable) }
  end

  describe "validations" do
    let(:project) { create(:project) }

    it "accepts a Game referenceable" do
      game = create(:game)
      ref = ProjectReference.new(project: project, referenceable: game)
      expect(ref).to be_valid
    end

    it "accepts a Collection referenceable" do
      collection = create(:collection)
      ref = ProjectReference.new(project: project, referenceable: collection)
      expect(ref).to be_valid
    end

    it "rejects unknown referenceable_type" do
      ref = ProjectReference.new(project: project,
                                 referenceable_type: "Channel", referenceable_id: 1)
      expect(ref).not_to be_valid
      expect(ref.errors[:referenceable_type]).to be_present
    end

    it "enforces uniqueness per project + referenceable_type + referenceable_id" do
      game = create(:game)
      ProjectReference.create!(project: project, referenceable: game)

      dup = ProjectReference.new(project: project, referenceable: game)
      expect(dup).not_to be_valid
    end

    it "permits the same referenceable across different projects" do
      other_project = create(:project)
      game = create(:game)
      ProjectReference.create!(project: project, referenceable: game)

      second = ProjectReference.new(project: other_project, referenceable: game)
      expect(second).to be_valid
    end
  end
end
