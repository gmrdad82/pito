require "rails_helper"

RSpec.describe Project, type: :model do
  subject { build(:project) }

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
    it { is_expected.to have_many(:project_references).dependent(:destroy) }
    it { is_expected.to have_many(:footages).dependent(:destroy) }
    it { is_expected.to have_many(:notes).dependent(:destroy) }
    it { is_expected.to have_many(:timelines).dependent(:destroy) }

    it "has_many :games through project_references" do
      assoc = Project.reflect_on_association(:games)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:through]).to eq(:project_references)
      expect(assoc.options[:source]).to eq(:referenceable)
      expect(assoc.options[:source_type]).to eq("Game")
    end

    it "has_many :collections through project_references" do
      assoc = Project.reflect_on_association(:collections)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:through]).to eq(:project_references)
      expect(assoc.options[:source_type]).to eq("Collection")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "default name" do
    it 'defaults to "Untitled project"' do
      tenant = create(:tenant)
      project = Project.create!(tenant: tenant)
      expect(project.name).to eq("Untitled project")
    end
  end

  describe "polymorphic references" do
    let(:tenant) { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }
    let(:game)       { create(:game, tenant: tenant) }
    let(:collection) { create(:collection, tenant: tenant) }

    it "collects games and collections via project_references" do
      ProjectReference.create!(project: project, tenant: tenant, referenceable: game)
      ProjectReference.create!(project: project, tenant: tenant, referenceable: collection)

      expect(project.games).to contain_exactly(game)
      expect(project.collections).to contain_exactly(collection)
    end

    it "supports zero references" do
      expect(project.games).to be_empty
      expect(project.collections).to be_empty
    end
  end
end
