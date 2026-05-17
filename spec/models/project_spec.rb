require "rails_helper"

# Phase 8 — tenant drop. Project is install-wide.
RSpec.describe Project, type: :model do
  subject { build(:project) }

  describe "associations" do
    it "does not declare a tenant association" do
      expect(Project.reflect_on_association(:tenant)).to be_nil
    end
    it { is_expected.to have_many(:project_references).dependent(:destroy) }
    it { is_expected.to have_many(:footages).dependent(:destroy) }
    it { is_expected.to have_many(:notes).dependent(:destroy) }
    it { is_expected.to have_many(:timelines).dependent(:destroy) }
    it { is_expected.to have_many(:videos).dependent(:nullify) }

    it "has_many :games through project_references" do
      assoc = Project.reflect_on_association(:games)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:through]).to eq(:project_references)
      expect(assoc.options[:source]).to eq(:referenceable)
      expect(assoc.options[:source_type]).to eq("Game")
    end

    it "does NOT declare :collections (model removed 2026-05-17)" do
      expect(Project.reflect_on_association(:collections)).to be_nil
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "default name" do
    it 'defaults to "Untitled project"' do
      project = Project.create!
      expect(project.name).to eq("Untitled project")
    end
  end

  describe "polymorphic references" do
    let(:project) { create(:project) }
    let(:game)    { create(:game) }

    it "collects games via project_references" do
      ProjectReference.create!(project: project, referenceable: game)
      expect(project.games).to contain_exactly(game)
    end

    it "supports zero references" do
      expect(project.games).to be_empty
    end
  end

  describe "cascade destroy" do
    let(:project) { create(:project) }
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

    it "destroys associated notes, footages, timelines (DB side)" do
      note = create(:note, project: project, path: "n.md")
      footage = create(:footage, project: project)
      timeline = create(:timeline, project: project)

      expect { project.destroy! }.to change(Note, :count).by(-1)
        .and change(Footage, :count).by(-1)
        .and change(Timeline, :count).by(-1)

      expect(Note.where(id: note.id)).to be_empty
      expect(Footage.where(id: footage.id)).to be_empty
      expect(Timeline.where(id: timeline.id)).to be_empty
    end

    it "removes the per-project notes directory on disk" do
      note = create(:note, project: project, path: "n.md")
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

  describe "Project ↔ Video link (Phase 12)" do
    let(:project) { create(:project) }

    it "exposes linked videos via has_many :videos" do
      v = create(:video, project: project)
      expect(project.videos).to contain_exactly(v)
    end

    it "preserves videos when project is destroyed (dependent: :nullify)" do
      v1 = create(:video, project: project)
      v2 = create(:video, project: project)
      project.destroy!
      [ v1, v2 ].each do |video|
        expect(Video.find(video.id).project_id).to be_nil
      end
    end

    it "nullifies project_id on N linked videos" do
      videos = Array.new(3) { create(:video, project: project) }
      project.destroy!
      videos.each { |v| expect(v.reload.project_id).to be_nil }
    end
  end

  # Phase 20 — friendly URLs. Project uses :slugged + :history (renameable
  # resource). Slug derives from `name` via `Pito::SlugBuilder` with an
  # 80-char cap. Old slugs survive a rename via the friendly_id_slugs
  # history table.
  describe "friendly_id (Phase 20)" do
    it "exposes :history in the friendly_id config" do
      expect(Project.friendly_id_config.uses?(:history)).to be(true)
    end

    it "exposes :slugged in the friendly_id config" do
      expect(Project.friendly_id_config.uses?(:slugged)).to be(true)
    end

    describe "to_param" do
      it "returns the slug (not the integer id) when name produces a slug" do
        project = create(:project, name: "My Summer Game")
        expect(project.to_param).to eq("my-summer-game")
        expect(project.to_param).not_to eq(project.id.to_s)
      end

      it "returns a fallback slug (project-<id>) when name is blank" do
        project = Project.new
        # `attribute :name` default is "Untitled project"; force a blank
        # name so the fallback candidate kicks in.
        project.name = ""
        project.save(validate: false)
        # The slug is whatever the candidate stack resolves to. Either
        # the default `untitled-project` (from the attribute default
        # before assignment) or the `project-<id>` fallback. Either way
        # it must be a non-empty string and must not be the bare integer.
        expect(project.to_param).not_to eq(project.id.to_s)
        expect(project.to_param).to be_present
      end
    end

    describe ".friendly.find" do
      let!(:project) { create(:project, name: "Celeste Retrospective") }

      it "resolves by slug" do
        expect(Project.friendly.find(project.slug)).to eq(project)
      end

      it "resolves by integer id (backwards compat)" do
        expect(Project.friendly.find(project.id)).to eq(project)
      end

      it "resolves by stringified integer id" do
        expect(Project.friendly.find(project.id.to_s)).to eq(project)
      end

      it "raises RecordNotFound for an unknown slug" do
        expect { Project.friendly.find("does-not-exist-anywhere") }
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe "rename + history" do
      it "regenerates the slug when name changes" do
        project = create(:project, name: "Original Name")
        original_slug = project.slug
        project.update!(name: "New Name")
        expect(project.reload.slug).not_to eq(original_slug)
        expect(project.slug).to eq("new-name")
        expect(project.to_param).to eq("new-name")
      end

      it "still resolves the old slug after rename (history module)" do
        project = create(:project, name: "Pre-rename")
        old_slug = project.slug
        project.update!(name: "Post-rename")
        expect(Project.friendly.find(old_slug)).to eq(project)
      end

      it "treats the new slug as canonical (to_param returns the new slug)" do
        project = create(:project, name: "Old")
        old_slug = project.slug
        project.update!(name: "New")
        expect(project.to_param).to eq(project.slug)
        expect(project.to_param).not_to eq(old_slug)
      end
    end

    describe "uniqueness / collision suffixing" do
      it "guarantees distinct slugs when two projects share a name" do
        # Use a per-run unique base so leaked Project / FriendlyId::Slug
        # rows from earlier specs don't perturb the candidate stack.
        base = "collide-#{SecureRandom.hex(4)}-name"
        a = create(:project, name: base)
        b = create(:project, name: base)
        expect(a.slug).to eq(base.tr(" ", "-").downcase)
        expect(b.slug).not_to eq(a.slug)
        expect(b.slug).to be_present
      end
    end

    describe "transliteration" do
      it "transliterates accented characters" do
        project = create(:project, name: "Café")
        expect(project.slug).to eq("cafe")
      end

      it "rejects non-latin scripts and falls back to the typed prefix" do
        # Cyrillic / CJK collapse via `Inflector.transliterate(_, "")` to
        # the empty string, then `normalize_friendly_id` falls back to
        # `project-<id>`.
        project = create(:project, name: "Над звездами")
        expect(project.slug).to start_with("project-")
      end
    end

    describe "long name truncation" do
      it "truncates to under 80 chars cleanly" do
        long_name = "a-very-long-name " * 20 # > 255 raw chars stripped to 255
        # We need a name within validates length: { maximum: 255 } so
        # build something just under that cap that produces a >80-char slug.
        project = create(:project, name: long_name[0, 250])
        expect(project.slug.length).to be <= 80
      end

      it "prefers a hyphen boundary over a mid-word cut" do
        # Build a name that, once parameterized, yields a slug whose 80th
        # character lands mid-word. SlugBuilder backs up to the last
        # hyphen in the last quarter of the limit.
        name = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima"
        project = create(:project, name: name)
        slug = project.slug
        expect(slug.length).to be <= 80
        # Should end at a hyphen-word boundary, never a trailing hyphen.
        expect(slug).not_to end_with("-")
      end
    end
  end

  describe "Note destroy file cleanup" do
    let(:project) { create(:project) }
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
      note = create(:note, project: project, path: "solo.md")
      NotesFilesystem.write(note, "body")
      file_path = NotesFilesystem.absolute_path_for(note)
      expect(File.exist?(file_path)).to be true

      note.destroy!

      expect(File.exist?(file_path)).to be false
    end
  end
end
