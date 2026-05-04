require "rails_helper"

RSpec.describe NotesFilesystem do
  let(:tenant) { create(:tenant) }
  let(:project) { create(:project, tenant: tenant) }
  let(:note) do
    create(:note, project: project, tenant: tenant, path: "first.md")
  end

  let(:tmp_root) { Dir.mktmpdir("pito-notes-spec") }

  before do
    @prev_root = ENV["PITO_NOTES_PATH"]
    ENV["PITO_NOTES_PATH"] = tmp_root
  end

  after do
    ENV["PITO_NOTES_PATH"] = @prev_root
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  describe ".write / .read" do
    it "writes the body to disk and reads it back" do
      described_class.write(note, "hello\n")
      expect(described_class.read(note)).to eq("hello\n")
    end

    it "creates the project directory tree on first write" do
      described_class.write(note, "x")
      expected_dir = File.join(tmp_root, tenant.id.to_s, "projects", project.id.to_s)
      expect(File.directory?(expected_dir)).to be true
    end
  end

  describe ".delete" do
    it "removes the file from disk" do
      described_class.write(note, "x")
      described_class.delete(note)
      expect(File.exist?(described_class.absolute_path_for(note))).to be false
    end

    it "is a no-op when the file is missing" do
      expect { described_class.delete(note) }.not_to raise_error
    end
  end

  describe ".rename" do
    it "moves the file to the new path" do
      described_class.write(note, "x")
      old_path = described_class.absolute_path_for(note)
      described_class.rename(note, "second.md")
      new_path = described_class.absolute_path_for(note, "second.md")
      expect(File.exist?(new_path)).to be true
      expect(File.exist?(old_path)).to be false
    end
  end

  describe ".slug_filename" do
    it "lowercases and slugifies titles" do
      expect(described_class.slug_filename("Hello World!")).to eq("hello-world.md")
    end

    it "strips path separators" do
      expect(described_class.slug_filename("a/b\\c")).to eq("a-b-c.md")
    end

    it "falls back to untitled-note.md for empty input" do
      expect(described_class.slug_filename("")).to eq("untitled-note.md")
    end
  end

  describe "path safety" do
    it "rejects absolute path strings" do
      expect { described_class.sanitize_relative("/etc/passwd") }.to raise_error(ArgumentError)
    end

    it "rejects traversal segments" do
      expect { described_class.sanitize_relative("../escape.md") }.to raise_error(ArgumentError)
    end

    it "ensures writes stay inside the project root" do
      # absolute path that escapes
      expect {
        described_class.send(:ensure_within_project!, note, "/tmp/elsewhere/foo.md")
      }.to raise_error(ArgumentError)
    end

    # ensure_within_project! uses File.realpath so symlinks are followed before
    # the prefix check (not just lexical File.expand_path).
    it "rejects a symlink inside the project that points outside the project" do
      project_dir = File.join(tmp_root, tenant.id.to_s, "projects", project.id.to_s)
      FileUtils.mkdir_p(project_dir)
      escape_target = Dir.mktmpdir("pito-notes-spec-escape")
      begin
        FileUtils.touch(File.join(escape_target, "secret.md"))
        symlink_path = File.join(project_dir, "trojan.md")
        File.symlink(File.join(escape_target, "secret.md"), symlink_path)

        expect {
          described_class.send(:ensure_within_project!, note, symlink_path)
        }.to raise_error(ArgumentError, /escapes project root/)
      ensure
        FileUtils.remove_entry(escape_target) if File.exist?(escape_target)
      end
    end

    it "accepts a symlink that resolves to a path inside the project" do
      project_dir = File.join(tmp_root, tenant.id.to_s, "projects", project.id.to_s)
      FileUtils.mkdir_p(project_dir)
      real_target = File.join(project_dir, "real.md")
      FileUtils.touch(real_target)
      symlink_path = File.join(project_dir, "alias.md")
      File.symlink(real_target, symlink_path)

      expect {
        described_class.send(:ensure_within_project!, note, symlink_path)
      }.not_to raise_error
    end

    it "accepts a not-yet-existing target file (the create-new-note flow)" do
      project_dir = File.join(tmp_root, tenant.id.to_s, "projects", project.id.to_s)
      FileUtils.mkdir_p(project_dir)
      target = File.join(project_dir, "brand-new.md")
      expect(File.exist?(target)).to be false

      expect {
        described_class.send(:ensure_within_project!, note, target)
      }.not_to raise_error
    end
  end
end
