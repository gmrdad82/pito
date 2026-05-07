require "rails_helper"

RSpec.describe "Notes", type: :request do
  let(:tenant) { Tenant.first || create(:tenant) }
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

  # Phase B post-commit (2026-05-04) — Note revamp.
  # /notes/:id/edit and /notes/new are gone. The show route IS the editor.
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

  describe "GET /notes/:id (the editor — show route)" do
    let!(:note) { create(:note, project: project, tenant: tenant) }

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
    let!(:note) { create(:note, project: project, tenant: tenant) }

    before do
      FileUtils.mkdir_p(NotesFilesystem.root_for(note))
      File.write(NotesFilesystem.absolute_path_for(note), "")
    end

    it "writes the body to disk and updates last_modified_at" do
      patch note_path(note), params: { note: { body: "# Hello\n\nWorld" } }
      note.reload
      # Title rename causes a file rename — read from the new on-disk path.
      expect(File.read(NotesFilesystem.absolute_path_for(note))).to include("Hello")
      expect(note.title).to eq("Hello")
    end

    it "auto-derives title from the first ATX H1 — title param is ignored" do
      # Even if a malicious client sends a `title` field, the server derives
      # from the body. The form has no title input by design.
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
      # Body: `# Hi\n\nfoo bar baz`. The `#` heading marker is consumed
      # by Commonmarker; tokens are: Hi, foo, bar, baz → 4 words.
      patch note_path(note), params: { note: { body: "# Hi\n\nfoo bar baz" } }
      note.reload
      expect(note.words_count).to eq(4)
    end

    it "ignores markdown syntax when counting words" do
      # User's example: `# Hi\nHow are you all doing?` → 6 words.
      patch note_path(note), params: { note: { body: "# Hi\nHow are you all doing?" } }
      expect(note.reload.words_count).to eq(6)
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

    it "removes file and record (file cleanup via the model callback)" do
      path = NotesFilesystem.absolute_path_for(note)
      expect {
        delete note_path(note)
      }.to change(Note, :count).by(-1)
      expect(File.exist?(path)).to be false
    end
  end

  describe "POST /notes/scan" do
    let(:tenant) { Tenant.first || create(:tenant) }

    it "enqueues NoteSyncJob" do
      tenant
      expect {
        post scan_notes_path
      }.to change(NoteSyncJob.jobs, :size).by(1)
    end
  end

  describe "GET /projects/:id (notes pane bulk-select markup)" do
    let!(:note) { create(:note, project: project, tenant: tenant) }

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
      # Phase B polish (2026-05-05) — checkboxes are always rendered;
      # the `[bulk]` enter / `[cancel]` exit toggles are gone in the
      # notes pane (mirrors Lane G's /channels and /videos shape).
      get project_path(project)
      expect(response.body).not_to include('click-&gt;bulk-select#enterBulk')
      expect(response.body).not_to include('click-&gt;bulk-select#exitBulk')
      expect(response.body).not_to include('data-bulk-select-target="bulkToggle"')
      # Header + per-row checkboxes ship in the DOM (always-on).
      expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
      expect(response.body).to include('change-&gt;bulk-select#toggleAll')
      expect(response.body).to include('data-bulk-select-target="checkbox"')
    end

    it "renders the words column reflecting the saved count (chars dropped)" do
      patch note_path(note), params: { note: { body: "# Title\n\nfoo bar" } }
      get project_path(project)
      # `words` is part of the `<th>` headers; `chars` is gone after the
      # 2026-05-06 cleanup.
      expect(response.body).to include(">words</a>").or include(">words</")
      expect(response.body).not_to match(/<th[^>]*>chars<\/th>/)
      expect(response.body).not_to match(/<th[^>]*>chars/)
    end
  end
end
