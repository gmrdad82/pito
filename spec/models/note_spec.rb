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

  # Phase 4 Wave 3.5+ — `/projects` index aggregates. The new
  # `notes_words_total` column on `projects` caches the SUM of
  # `notes.words_count` per project so the index can render a word total
  # rather than a row count. The cache is maintained by after_save /
  # after_destroy callbacks here.
  describe "project.notes_words_total aggregate cache" do
    let(:tenant)  { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }

    it "increases by a new note's words_count on create" do
      expect {
        # `body_for_counts` triggers `recompute_counts` so words_count
        # lands at the markdown-aware computed value (here 4).
        n = build(:note, project: project, tenant: tenant)
        n.body_for_counts = "one two three four"
        n.save!
      }.to change { project.reload.notes_words_total }.from(0).to(4)
    end

    it "decreases by a destroyed note's words_count" do
      a = build(:note, project: project, tenant: tenant)
      a.body_for_counts = "alpha bravo charlie delta echo"
      a.save!
      b = build(:note, project: project, tenant: tenant)
      b.body_for_counts = "foxtrot golf"
      b.save!
      project.reload
      expect(project.notes_words_total).to eq(7)

      expect {
        a.destroy!
      }.to change { project.reload.notes_words_total }.from(7).to(2)
    end

    it "recomputes when an existing note's words_count changes" do
      note = build(:note, project: project, tenant: tenant)
      note.body_for_counts = "one two three"
      note.save!
      project.reload
      expect(project.notes_words_total).to eq(3)

      note.body_for_counts = "one two three four five six seven"
      note.save!
      expect(project.reload.notes_words_total).to eq(7)
    end

    it "does not recompute when an unrelated column changes" do
      note = build(:note, project: project, tenant: tenant)
      note.body_for_counts = "one two three"
      note.save!
      project.reload
      expect(project.notes_words_total).to eq(3)

      # Title-only update — body_for_counts is nil this time, words_count
      # stays at 3, callback should no-op.
      expect {
        note.update!(title: "renamed")
      }.not_to change { project.reload.notes_words_total }
    end

    it "refreshes both projects when a note moves between projects" do
      old_project = project
      new_project = create(:project, tenant: tenant)
      note = build(:note, project: old_project, tenant: tenant)
      note.body_for_counts = "one two three"
      note.save!
      old_project.reload
      expect(old_project.notes_words_total).to eq(3)

      note.update!(project: new_project)
      expect(old_project.reload.notes_words_total).to eq(0)
      expect(new_project.reload.notes_words_total).to eq(3)
    end

    it "no-ops cleanly when the parent project is destroyed (cascade)" do
      n = build(:note, project: project, tenant: tenant)
      n.body_for_counts = "one two three"
      n.save!
      project.reload
      # Project#destroy cascades to notes via dependent: :destroy. By
      # the time the note's after_destroy fires, the project row is
      # gone; callback must silently no-op.
      expect { project.destroy! }.not_to raise_error
    end
  end

  describe "chars_count column removal" do
    it "no longer exposes a chars_count attribute" do
      expect(Note.column_names).not_to include("chars_count")
    end
  end

  # Integration test — assigning `body_for_counts` before save persists
  # the recomputed word count to the row. The markdown-aware tokenizer
  # itself lives in `NoteHelper.word_count`; its edge cases are covered
  # in `spec/helpers/note_helper_spec.rb`. This describe block only
  # asserts the `before_save :recompute_counts` callback wires the two
  # together end-to-end.
  describe "words_count recomputation (integration)" do
    let(:tenant)  { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }
    let(:note)    { create(:note, project: project, tenant: tenant) }

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
