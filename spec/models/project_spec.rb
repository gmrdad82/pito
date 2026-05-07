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

    # Phase 5A — re-pin Current.tenant onto the explicitly-created
    # tenant so the BelongsToTenant default scope sees the rows
    # this block builds.
    before { Current.tenant = tenant }

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

  # Phase B (2026-05-04) — cascade-delete verification. Project destroy
  # tears down notes, footages, timelines, and project_references at the
  # DB level, AND removes the per-project notes directory on disk.
  describe "cascade destroy" do
    let(:tenant) { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }
    let(:tmp_root) do
      Rails.root.join("tmp", "test-pito-notes", SecureRandom.hex(6)).to_s
    end

    before do
      # Phase 5A — re-pin Current.tenant onto the explicitly-created
      # tenant so the cascade has_many associations (which apply
      # the default scope) see this block's rows.
      Current.tenant = tenant
      @prev_root = ENV["PITO_NOTES_PATH"]
      ENV["PITO_NOTES_PATH"] = tmp_root
    end

    after do
      ENV["PITO_NOTES_PATH"] = @prev_root
      FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
    end

    it "destroys associated notes, footages, timelines (DB side)" do
      note = create(:note, project: project, tenant: tenant, path: "n.md")
      footage = create(:footage, project: project, tenant: tenant)
      timeline = create(:timeline, project: project, tenant: tenant)

      expect { project.destroy! }.to change(Note, :count).by(-1)
        .and change(Footage, :count).by(-1)
        .and change(Timeline, :count).by(-1)

      expect(Note.where(id: note.id)).to be_empty
      expect(Footage.where(id: footage.id)).to be_empty
      expect(Timeline.where(id: timeline.id)).to be_empty
    end

    it "removes the per-project notes directory on disk" do
      note = create(:note, project: project, tenant: tenant, path: "n.md")
      NotesFilesystem.write(note, "hello")
      project_dir = NotesFilesystem.project_dir(project)
      expect(File.directory?(project_dir)).to be true

      project.destroy!

      expect(File.directory?(project_dir)).to be false
    end

    it "is a no-op on disk when the project has no notes folder yet" do
      project_dir = NotesFilesystem.project_dir(project)
      expect(File.directory?(project_dir)).to be false
      expect { project.destroy! }.not_to raise_error
    end
  end

  # Phase B (2026-05-04) — Note#before_destroy removes the underlying
  # markdown file. Verified independently of the project cascade so a
  # solo `note.destroy` (e.g. via NotesController#destroy) is also clean.
  describe "Note destroy file cleanup" do
    let(:tenant) { create(:tenant) }
    let(:project) { create(:project, tenant: tenant) }
    let(:tmp_root) do
      Rails.root.join("tmp", "test-pito-notes", SecureRandom.hex(6)).to_s
    end

    before do
      @prev_root = ENV["PITO_NOTES_PATH"]
      ENV["PITO_NOTES_PATH"] = tmp_root
    end

    after do
      ENV["PITO_NOTES_PATH"] = @prev_root
      FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
    end

    it "removes the on-disk file when the note is destroyed directly" do
      note = create(:note, project: project, tenant: tenant, path: "solo.md")
      NotesFilesystem.write(note, "body")
      file_path = NotesFilesystem.absolute_path_for(note)
      expect(File.exist?(file_path)).to be true

      note.destroy!

      expect(File.exist?(file_path)).to be false
    end
  end
end
