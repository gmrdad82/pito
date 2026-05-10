require "rails_helper"

# Phase 8 — tenant drop. Note path uniqueness is now per-project.
RSpec.describe Note, type: :model do
  subject { build(:note) }

  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it "does not declare a tenant association" do
      expect(Note.reflect_on_association(:tenant)).to be_nil
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:path) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:last_modified_at) }
    it { is_expected.to validate_length_of(:title).is_at_most(80) }

    it "enforces path uniqueness scoped to project" do
      project = create(:project)
      create(:note, project: project, path: "first.md")
      dup = build(:note, project: project, path: "first.md")
      expect(dup).not_to be_valid
    end

    it "permits the same path on a different project" do
      project_a = create(:project)
      project_b = create(:project)
      create(:note, project: project_a, path: "first.md")
      sibling = build(:note, project: project_b, path: "first.md")
      expect(sibling).to be_valid
    end
  end

  describe "default title" do
    it 'defaults to "Untitled note"' do
      project = create(:project)
      note = Note.create!(project: project, path: "x.md", last_modified_at: Time.current)
      expect(note.title).to eq("Untitled note")
    end
  end

  describe "embedding column" do
    it "is nullable on create (Voyage gating may leave it null)" do
      project = create(:project)
      note = Note.create!(project: project, path: "x.md", last_modified_at: Time.current)
      expect(note.embedding).to be_nil
    end
  end

  describe "neighbor integration" do
    it "wires has_neighbors :embedding so .nearest_neighbors is available" do
      expect(Note).to respond_to(:nearest_neighbors)
    end
  end

  describe "counter_cache on project" do
    let(:project) { create(:project) }

    it "increments project.notes_count when a note is created" do
      expect {
        create(:note, project: project)
      }.to change { project.reload.notes_count }.from(0).to(1)
    end

    it "decrements project.notes_count when a note is destroyed" do
      note = create(:note, project: project)
      project.reload
      expect(project.notes_count).to eq(1)

      expect {
        note.destroy!
      }.to change { project.reload.notes_count }.from(1).to(0)
    end
  end

  describe "project.notes_words_total aggregate cache" do
    let(:project) { create(:project) }

    it "increases by a new note's words_count on create" do
      expect {
        n = build(:note, project: project)
        n.body_for_counts = "one two three four"
        n.save!
      }.to change { project.reload.notes_words_total }.from(0).to(4)
    end

    it "decreases by a destroyed note's words_count" do
      a = build(:note, project: project)
      a.body_for_counts = "alpha bravo charlie delta echo"
      a.save!
      b = build(:note, project: project)
      b.body_for_counts = "foxtrot golf"
      b.save!
      project.reload
      expect(project.notes_words_total).to eq(7)

      expect {
        a.destroy!
      }.to change { project.reload.notes_words_total }.from(7).to(2)
    end

    it "recomputes when an existing note's words_count changes" do
      note = build(:note, project: project)
      note.body_for_counts = "one two three"
      note.save!
      project.reload
      expect(project.notes_words_total).to eq(3)

      note.body_for_counts = "one two three four five six seven"
      note.save!
      expect(project.reload.notes_words_total).to eq(7)
    end

    it "does not recompute when an unrelated column changes" do
      note = build(:note, project: project)
      note.body_for_counts = "one two three"
      note.save!
      project.reload
      expect(project.notes_words_total).to eq(3)

      expect {
        note.update!(title: "renamed")
      }.not_to change { project.reload.notes_words_total }
    end

    it "refreshes both projects when a note moves between projects" do
      old_project = project
      new_project = create(:project)
      note = build(:note, project: old_project)
      note.body_for_counts = "one two three"
      note.save!
      old_project.reload
      expect(old_project.notes_words_total).to eq(3)

      note.update!(project: new_project)
      expect(old_project.reload.notes_words_total).to eq(0)
      expect(new_project.reload.notes_words_total).to eq(3)
    end

    it "no-ops cleanly when the parent project is destroyed (cascade)" do
      n = build(:note, project: project)
      n.body_for_counts = "one two three"
      n.save!
      project.reload
      expect { project.destroy! }.not_to raise_error
    end
  end

  describe "chars_count column removal" do
    it "no longer exposes a chars_count attribute" do
      expect(Note.column_names).not_to include("chars_count")
    end
  end

  describe "words_count recomputation (integration)" do
    let(:project) { create(:project) }
    let(:note)    { create(:note, project: project) }

    it "stays at 0 when body_for_counts is not assigned" do
      expect(note.words_count).to eq(0)
    end

    it "delegates to NoteHelper.word_count and persists the result on save" do
      note.body_for_counts = "# Hello\n\nWorld and again"
      note.save!
      expect(note.words_count).to eq(NoteHelper.word_count("# Hello\n\nWorld and again"))
      expect(note.words_count).to eq(4)
    end

    it "no longer exposes a `.calculate_word_count` class method" do
      expect(described_class).not_to respond_to(:calculate_word_count)
    end
  end
end
