require "rails_helper"

RSpec.describe "Notes", type: :request do
  let(:tenant) { create(:tenant) }
  let(:project) { create(:project, tenant: tenant) }

  let(:tmp_root) { Dir.mktmpdir("pito-notes-spec") }

  before do
    @prev_root = ENV["PITO_NOTES_PATH"]
    ENV["PITO_NOTES_PATH"] = tmp_root
  end

  after do
    ENV["PITO_NOTES_PATH"] = @prev_root
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  describe "POST /projects/:project_id/notes (default-create)" do
    it "writes an empty file and creates the Note record in one transaction" do
      expect {
        post project_notes_path(project)
      }.to change(Note, :count).by(1)

      note = Note.last
      expect(note.title).to eq("Untitled note")
      expect(File.exist?(NotesFilesystem.absolute_path_for(note))).to be true
    end

    it "redirects to edit on success" do
      post project_notes_path(project)
      expect(response).to redirect_to(edit_note_path(Note.last))
    end

    context "when the lock is fresh" do
      before { tenant.update!(notes_syncing_at: 1.minute.ago) }

      it "redirects with the syncing alert (HTML)" do
        post project_notes_path(project)
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include("syncing")
      end

      it "returns 423 Locked for JSON requests" do
        post project_notes_path(project),
             params: {}.to_json,
             headers: { "ACCEPT" => "application/json", "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:locked)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("notes_syncing")
        expect(body["retry_after"]).to eq(30)
      end
    end
  end

  describe "PATCH /notes/:id (update)" do
    let!(:note) { create(:note, project: project, tenant: tenant) }

    before do
      FileUtils.mkdir_p(NotesFilesystem.root_for(note))
      File.write(NotesFilesystem.absolute_path_for(note), "")
    end

    it "writes the body to disk and updates last_modified_at" do
      patch note_path(note), params: { note: { body: "# Hello\n\nWorld" } }
      expect(File.read(NotesFilesystem.absolute_path_for(note))).to include("Hello")
      expect(note.reload.title).to eq("Hello")
    end

    it "renames the file when title changes" do
      patch note_path(note), params: { note: { title: "Renamed", body: "x" } }
      note.reload
      expect(note.title).to eq("Renamed")
      expect(note.path).to eq("renamed.md")
    end

    context "when the lock is fresh" do
      before { tenant.update!(notes_syncing_at: 1.minute.ago) }

      it "returns 423 Locked for JSON" do
        patch note_path(note),
              params: { note: { body: "x" } }.to_json,
              headers: { "ACCEPT" => "application/json", "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:locked)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("notes_syncing")
      end
    end
  end

  describe "DELETE /notes/:id" do
    let!(:note) { create(:note, project: project, tenant: tenant) }

    before do
      FileUtils.mkdir_p(NotesFilesystem.root_for(note))
      File.write(NotesFilesystem.absolute_path_for(note), "x")
    end

    it "removes file and record" do
      path = NotesFilesystem.absolute_path_for(note)
      expect {
        delete note_path(note)
      }.to change(Note, :count).by(-1)
      expect(File.exist?(path)).to be false
    end
  end

  describe "POST /notes/scan" do
    let(:tenant) { create(:tenant) }

    it "enqueues NoteSyncJob" do
      tenant
      expect {
        post scan_notes_path
      }.to change(NoteSyncJob.jobs, :size).by(1)
    end
  end
end
