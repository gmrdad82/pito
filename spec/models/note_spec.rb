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

  # Phase 4 Wave 2 — `/projects` index revamp. The project row's
  # `notes_count` powers the display + sort; counter must keep in sync.
  describe "counter_cache on project" do
    let(:tenant)  { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }

    it "increments project.notes_count when a note is created" do
      expect {
        create(:note, project: project, tenant: tenant)
      }.to change { project.reload.notes_count }.from(0).to(1)
    end

    it "decrements project.notes_count when a note is destroyed" do
      note = create(:note, project: project, tenant: tenant)
      project.reload
      expect(project.notes_count).to eq(1)

      expect {
        note.destroy!
      }.to change { project.reload.notes_count }.from(1).to(0)
    end
  end

  describe "chars_count / words_count recomputation" do
    let(:tenant)  { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }
    let(:note)    { create(:note, project: project, tenant: tenant) }

    it "stays at 0 / 0 when body_for_counts is not assigned" do
      expect(note.chars_count).to eq(0)
      expect(note.words_count).to eq(0)
    end

    it "recomputes from body_for_counts on save" do
      note.body_for_counts = "# Hello\n\nWorld and again"
      note.save!
      expect(note.chars_count).to eq("# Hello\n\nWorld and again".chars.size)
      expect(note.words_count).to eq(5) # "#", "Hello", "World", "and", "again"
    end

    it "treats an empty body as zero" do
      note.body_for_counts = ""
      note.save!
      expect(note.chars_count).to eq(0)
      expect(note.words_count).to eq(0)
    end

    it "counts unicode codepoints, not bytes" do
      note.body_for_counts = "héllo"
      note.save!
      expect(note.chars_count).to eq(5)
      expect(note.words_count).to eq(1)
    end
  end
end
