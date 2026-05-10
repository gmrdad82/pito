require "rails_helper"

# Phase 8 — tenant drop. Notes live install-wide; the lock is now an
# AppSetting key managed by `NotesLockGuard`.
RSpec.describe "Notes", type: :request do
  let(:project) { create(:project) }

  let(:tmp_root) { Dir.mktmpdir("pito-notes-spec") }

  before do
    @prev_root = ENV["PITO_NOTES_PATH"]
    ENV["PITO_NOTES_PATH"] = tmp_root
  end

  after do
    ENV["PITO_NOTES_PATH"] = @prev_root
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
    NotesLockGuard.release!
  end

  describe "deprecated routes" do
    it "has no edit_note_path helper" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:edit_note_path)
    end

    it "has no new_note_path helper" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:new_note_path)
    end
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

    it "redirects to show on success (the show route IS the editor)" do
      post project_notes_path(project)
      expect(response).to redirect_to(note_path(Note.last))
    end

    context "when the lock is fresh" do
      before { NotesLockGuard.acquire! }

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

  describe "GET /notes/:id (the editor — show route)" do
    let!(:note) { create(:note, project: project) }

    before do
      FileUtils.mkdir_p(NotesFilesystem.root_for(note))
      File.write(NotesFilesystem.absolute_path_for(note), "# Hello\n\nWorld")
    end

    it "renders the two-pane editor with markdown-editor + unsaved-form controllers" do
      get note_path(note)
      expect(response).to be_successful
      expect(response.body).to include('data-controller="markdown-editor unsaved-form"')
      expect(response.body).to include('data-markdown-editor-target="source"')
      expect(response.body).to include('data-markdown-editor-target="preview"')
      expect(response.body).to include('data-markdown-editor-target="wordCount"')
    end

    it "does NOT render a chars status" do
      get note_path(note)
      expect(response.body).not_to include('data-markdown-editor-target="charCount"')
      expect(response.body).not_to match(/<span[^>]*>[^<]*<\/span>\s*chars/)
    end

    it "does NOT render a title input" do
      get note_path(note)
      expect(response.body).not_to match(/<input[^>]*name="note\[title\]"/)
    end

    it "renders the source body in the textarea" do
      get note_path(note)
      expect(response.body).to include("# Hello")
    end
  end

  describe "PATCH /notes/:id (update)" do
    let!(:note) { create(:note, project: project) }

    before do
      FileUtils.mkdir_p(NotesFilesystem.root_for(note))
      File.write(NotesFilesystem.absolute_path_for(note), "")
    end

    it "writes the body to disk and updates last_modified_at" do
      patch note_path(note), params: { note: { body: "# Hello\n\nWorld" } }
      note.reload
      expect(File.read(NotesFilesystem.absolute_path_for(note))).to include("Hello")
      expect(note.title).to eq("Hello")
    end

    it "auto-derives title from the first ATX H1 — title param is ignored" do
      patch note_path(note), params: { note: { title: "spoofed", body: "# Real Title\n\nbody" } }
      expect(note.reload.title).to eq("Real Title")
    end

    it "renames the file when the derived title changes" do
      patch note_path(note), params: { note: { body: "# Renamed\n\nx" } }
      note.reload
      expect(note.title).to eq("Renamed")
      expect(note.path).to eq("renamed.md")
    end

    it "recomputes words_count via the markdown-aware tokenizer" do
      patch note_path(note), params: { note: { body: "# Hi\n\nfoo bar baz" } }
      note.reload
      expect(note.words_count).to eq(4)
    end

    it "ignores markdown syntax when counting words" do
      patch note_path(note), params: { note: { body: "# Hi\nHow are you all doing?" } }
      expect(note.reload.words_count).to eq(6)
    end

    context "when the lock is fresh" do
      before { NotesLockGuard.acquire! }

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
    let!(:note) { create(:note, project: project) }

    before do
      FileUtils.mkdir_p(NotesFilesystem.root_for(note))
      File.write(NotesFilesystem.absolute_path_for(note), "x")
    end

    it "removes file and record (file cleanup via the model callback)" do
      path = NotesFilesystem.absolute_path_for(note)
      expect {
        delete note_path(note)
      }.to change(Note, :count).by(-1)
      expect(File.exist?(path)).to be false
    end
  end

  describe "POST /notes/scan" do
    it "enqueues NoteSyncJob" do
      expect {
        post scan_notes_path
      }.to change(NoteSyncJob.jobs, :size).by(1)
    end
  end

  # Phase 20 — friendly URLs. Notes use `path` as their natural identifier
  # (no friendly_id wiring); routes use a `*path` glob so slash-bearing
  # paths reach the controller intact. The controller's `set_note`
  # supports both the new path-based key (`params[:path]`) and a legacy
  # integer-id fallback (`params[:id]`) for older bookmarks.
  #
  # We test `set_note` at the unit level here — the integration-level
  # `GET /notes/:id` tests above already exercise the responder layer,
  # and Phase 20's actual change is the param resolution logic itself.
  describe "Phase 20 — path-as-identifier resolution (NotesController#set_note)" do
    let!(:nested_note) do
      # Unique path so the spec resolves to exactly one record even when
      # other test rows leak across runs (path uniqueness is per-project,
      # not install-wide, so a leaked sibling Note on a different project
      # would otherwise contaminate `find_by!(path:)`).
      unique = "phase20-path-spec-#{SecureRandom.hex(4)}"
      n = create(:note, project: project, path: "#{unique}/example.md")
      FileUtils.mkdir_p(NotesFilesystem.root_for(n))
      File.write(NotesFilesystem.absolute_path_for(n), "# Hello\n\nbody")
      n
    end

    def with_controller_params(params_hash)
      controller = NotesController.new
      controller.params = ActionController::Parameters.new(params_hash)
      controller
    end

    it "resolves a slash-bearing path through find_by!(path:)" do
      controller = with_controller_params(path: nested_note.path)
      controller.send(:set_note)
      expect(controller.instance_variable_get(:@note)).to eq(nested_note)
    end

    it "resolves an integer-id key via the legacy fallback" do
      controller = with_controller_params(id: nested_note.id.to_s)
      controller.send(:set_note)
      expect(controller.instance_variable_get(:@note)).to eq(nested_note)
    end

    it "raises RecordNotFound when the path matches no record" do
      controller = with_controller_params(path: "no/such/note.md")
      expect { controller.send(:set_note) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "Note#to_param returns the on-disk path verbatim (slashes preserved)" do
      expect(nested_note.to_param).to eq(nested_note.path)
      expect(nested_note.to_param).to include("/")
    end
  end

  describe "GET /projects/:id (notes pane bulk-select markup)" do
    let!(:note) { create(:note, project: project) }

    before do
      FileUtils.mkdir_p(NotesFilesystem.root_for(note))
      File.write(NotesFilesystem.absolute_path_for(note), "")
    end

    it "renders the notes pane with the bulk-select controller wired" do
      get project_path(project)
      expect(response).to be_successful
      expect(response.body).to include('data-controller="bulk-select"')
      expect(response.body).to include('data-bulk-select-entity-name-value="notes"')
      expect(response.body).to include('data-bulk-select-delete-type-value="note"')
    end

    it "renders always-on bulk-select markup (no [bulk] toggle)" do
      get project_path(project)
      expect(response.body).not_to include('click-&gt;bulk-select#enterBulk')
      expect(response.body).not_to include('click-&gt;bulk-select#exitBulk')
      expect(response.body).not_to include('data-bulk-select-target="bulkToggle"')
      expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
      expect(response.body).to include('change-&gt;bulk-select#toggleAll')
      expect(response.body).to include('data-bulk-select-target="checkbox"')
    end

    it "renders the words column reflecting the saved count (chars dropped)" do
      patch note_path(note), params: { note: { body: "# Title\n\nfoo bar" } }
      get project_path(project)
      expect(response.body).to include(">words</a>").or include(">words</")
      expect(response.body).not_to match(/<th[^>]*>chars<\/th>/)
      expect(response.body).not_to match(/<th[^>]*>chars/)
    end
  end
end
