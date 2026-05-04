require "rails_helper"

RSpec.describe Note, type: :model do
  subject { build(:note) }

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
    it { is_expected.to belong_to(:project) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:path) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:last_modified_at) }
    it { is_expected.to validate_length_of(:title).is_at_most(80) }

    it "enforces path uniqueness scoped to tenant" do
      tenant = create(:tenant)
      project = create(:project, tenant: tenant)
      create(:note, project: project, path: "first.md")
      dup = build(:note, project: project, path: "first.md")
      expect(dup).not_to be_valid
    end
  end

  describe "default title" do
    it 'defaults to "Untitled note"' do
      tenant = create(:tenant)
      project = create(:project, tenant: tenant)
      note = Note.create!(tenant: tenant, project: project,
                          path: "x.md", last_modified_at: Time.current)
      expect(note.title).to eq("Untitled note")
    end
  end

  describe "embedding column" do
    it "is nullable on create (Voyage gating may leave it null)" do
      tenant = create(:tenant)
      project = create(:project, tenant: tenant)
      note = Note.create!(tenant: tenant, project: project,
                          path: "x.md", last_modified_at: Time.current)
      expect(note.embedding).to be_nil
    end
  end

  describe "neighbor integration" do
    it "wires has_neighbors :embedding so .nearest_neighbors is available" do
      expect(Note).to respond_to(:nearest_neighbors)
    end
  end
end
