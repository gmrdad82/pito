require "rails_helper"

RSpec.describe Notes::EmbedJob, type: :job do
  let!(:project) { create(:project) }
  let!(:note) { create(:note, project: project, path: "alpha.md") }

  let(:tmp_root) { Dir.mktmpdir("pito-notes-embed-spec") }

  before do
    @prev_root = ENV["PITO_NOTES_PATH"]
    ENV["PITO_NOTES_PATH"] = tmp_root
    FileUtils.mkdir_p(NotesFilesystem.root_for(note))
    File.write(NotesFilesystem.absolute_path_for(note), "# alpha\n\nBody.")

    # Allow Meilisearch upsert HTTP traffic to fail silently — most specs
    # focus on the Voyage gate, not the search path.
    stub_request(:post, /127\.0\.0\.1:7727/).to_return(status: 200)
  end

  after do
    ENV["PITO_NOTES_PATH"] = @prev_root
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  # Phase 4 §3.5 (Phase B revamp, 2026-05-04) — gating now reads the
  # per-target `voyage_indexing_project_notes?` flag AND the
  # `voyage_configured?` (key present) check. The job must short-circuit
  # cleanly when either is false.
  describe "#perform with voyage_indexing_project_notes? false (default)" do
    before do
      AppSetting.find_or_create_by!(key: "voyage_test") { |r| r.value = "x" }
        .update!(voyage_index_project_notes: false)
    end

    it "does NOT call the Voyage API" do
      described_class.new.perform(note.id)
      expect(WebMock).not_to have_requested(:post, /api\.voyageai\.com/)
    end

    it "leaves notes.embedding NULL" do
      described_class.new.perform(note.id)
      expect(note.reload.embedding).to be_nil
    end

    it "still indexes the note text in Meilisearch (BM25 only)" do
      described_class.new.perform(note.id)
      expect(WebMock).to have_requested(:post, %r{notes_test/documents}).once
    end
  end

  describe "#perform with voyage_indexing_project_notes? true and key configured" do
    let(:fake_embedding) { Array.new(1024) { 0.0 } }

    before do
      record = AppSetting.first || AppSetting.create!(key: "voyage_test", value: "x")
      record.update!(voyage_api_key: "vk_appsetting", voyage_index_project_notes: true)

      stub_request(:post, "https://api.voyageai.com/v1/embeddings")
        .to_return(
          status: 200,
          body: { data: [ { embedding: fake_embedding } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "calls Voyage once and writes the embedding to pgvector" do
      described_class.new.perform(note.id)
      expect(WebMock).to have_requested(:post, "https://api.voyageai.com/v1/embeddings").once
      expect(note.reload.embedding).to be_present
    end

    it "indexes the note in Meilisearch with the embedding payload" do
      described_class.new.perform(note.id)
      expect(WebMock).to(have_requested(:post, %r{notes_test/documents}).with { |req|
        body = JSON.parse(req.body)
        body.first.key?("_vectors")
      })
    end

    it "uses the AppSetting key as the bearer token" do
      described_class.new.perform(note.id)
      expect(WebMock).to(have_requested(:post, "https://api.voyageai.com/v1/embeddings").with { |req|
        req.headers["Authorization"] == "Bearer vk_appsetting"
      })
    end
  end

  # Defensive belt-and-suspenders: the model validation prevents this combo
  # at the form boundary, but if migration drift or direct SQL writes get
  # the flag and key out of sync, the job's dual check must still
  # short-circuit before any Voyage HTTP call.
  describe "#perform with voyage_indexing_project_notes? true but key blank" do
    before do
      record = AppSetting.first || AppSetting.create!(key: "voyage_test", value: "x")
      # Bypass the model validation deliberately — this is the scenario we
      # want to defend against.
      record.update_columns(voyage_api_key: nil, voyage_index_project_notes: true)
    end

    it "does NOT call the Voyage API" do
      described_class.new.perform(note.id)
      expect(WebMock).not_to have_requested(:post, /api\.voyageai\.com/)
    end

    it "leaves notes.embedding NULL" do
      described_class.new.perform(note.id)
      expect(note.reload.embedding).to be_nil
    end

    it "still indexes the note text in Meilisearch (BM25 only)" do
      described_class.new.perform(note.id)
      expect(WebMock).to have_requested(:post, %r{notes_test/documents}).once
    end
  end

  # Bootstrap fallback: AppSetting key is blank, but credentials carry one.
  # The flag still must be on for the call to fire, AND
  # `voyage_configured?` requires the AppSetting key to be present, so
  # this branch documents that the credentials fallback alone does NOT
  # bypass the dual check. The key MUST live on AppSetting for the job
  # to fire.
  describe "#perform when only credentials carry the key (no AppSetting key)" do
    before do
      record = AppSetting.first || AppSetting.create!(key: "voyage_test", value: "x")
      record.update_columns(voyage_api_key: nil, voyage_index_project_notes: true)

      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, anything, :api_key).and_return("voyage-key-from-creds")
    end

    it "does NOT call Voyage (voyage_configured? gate is the AppSetting key)" do
      described_class.new.perform(note.id)
      expect(WebMock).not_to have_requested(:post, /api\.voyageai\.com/)
    end
  end

  it "is a no-op when the note is missing" do
    expect {
      described_class.new.perform(999_999)
    }.not_to raise_error
  end
end
