require "rails_helper"

RSpec.describe NoteSyncJob, type: :job do
  let!(:tenant) { create(:tenant) }
  let!(:project) { create(:project, tenant: tenant) }

  let(:tmp_root) { Dir.mktmpdir("pito-notes-spec") }
  let(:project_dir) { File.join(tmp_root, tenant.id.to_s, "projects", project.id.to_s) }

  before do
    # Phase 5A — re-pin Current.tenant onto the explicitly-created
    # tenant so spec-side assertions like `Note.count` (which apply
    # the BelongsToTenant default scope) see the rows the job
    # creates. The job itself also pins Current.tenant for the
    # duration of `#perform`.
    Current.tenant = tenant
    @prev_root = ENV["PITO_NOTES_PATH"]
    ENV["PITO_NOTES_PATH"] = tmp_root
    FileUtils.mkdir_p(project_dir)
  end

  after do
    ENV["PITO_NOTES_PATH"] = @prev_root
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  describe "#perform" do
    it "sets and clears notes_syncing_at via the ensure block" do
      described_class.new.perform(tenant.id)
      expect(tenant.reload.notes_syncing_at).to be_nil
    end

    it "clears notes_syncing_at even when reconcile raises" do
      allow(Dir).to receive(:glob).and_raise(StandardError, "boom")
      expect {
        described_class.new.perform(tenant.id)
      }.to raise_error(StandardError, "boom")
      expect(tenant.reload.notes_syncing_at).to be_nil
    end

    context "ADD branch — file on disk, no DB record" do
      it "creates a Note record from the file" do
        path = File.join(project_dir, "alpha.md")
        File.write(path, "# Alpha title\n\nBody.")

        expect {
          described_class.new.perform(tenant.id)
        }.to change(Note, :count).by(1)

        note = Note.last
        expect(note.title).to eq("Alpha title")
        expect(note.path).to eq("alpha.md")
      end

      it "enqueues Notes::EmbedJob for the new note" do
        path = File.join(project_dir, "beta.md")
        File.write(path, "# Beta")

        expect {
          described_class.new.perform(tenant.id)
        }.to change(Notes::EmbedJob.jobs, :size).by(1)
      end
    end

    context "CHANGE branch — file mtime > note.last_modified_at" do
      let!(:note) do
        create(:note, project: project, tenant: tenant, path: "old.md",
                      title: "old", last_modified_at: 2.hours.ago)
      end

      before do
        path = File.join(project_dir, note.path)
        File.write(path, "# new title")
        now = Time.current.to_time
        File.utime(now, now, path)
      end

      it "updates title and last_modified_at and enqueues EmbedJob" do
        expect {
          described_class.new.perform(tenant.id)
        }.to change(Notes::EmbedJob.jobs, :size).by(1)
        note.reload
        expect(note.title).to eq("new title")
        expect(note.last_modified_at).to be > 5.minutes.ago
      end
    end

    context "DELETE branch — DB record without file" do
      let!(:orphan) do
        create(:note, project: project, tenant: tenant, path: "orphan.md")
      end

      it "destroys the orphan record" do
        expect {
          described_class.new.perform(tenant.id)
        }.to change(Note, :count).by(-1)
      end
    end

    it "is a no-op when the tenant is missing" do
      expect {
        described_class.new.perform(999_999)
      }.not_to raise_error
    end
  end
end
