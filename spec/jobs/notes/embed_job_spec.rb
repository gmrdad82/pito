require "rails_helper"

RSpec.describe Notes::EmbedJob, type: :job do
  let!(:project) { create(:project) }
  let!(:note) { create(:note, project: project, path: "alpha.md") }

  let(:tmp_root) { Dir.mktmpdir("pito-notes-embed-spec") }

  # Phase 29 (settings refactor) — the per-target
  # `voyage_index_project_notes` flag column was dropped along with the
  # Voyage.ai pane. `voyage_indexing_project_notes?` is now a thin alias
  # for `voyage_configured?` (credentials key presence is the only
  # signal). Specs stub the credentials key directly; the dual check in
  # the job still ANDs the two predicates, which both resolve to the
  # same boolean today.
  def stub_voyage_credentials_key(value)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:voyage, :api_key).and_return(value)
  end

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

  # No credentials key configured → the job's gate short-circuits and
  # we never hit Voyage. The note still indexes in Meilisearch (BM25
  # only) so keyword search keeps working.
  describe "#perform with no Voyage credentials key" do
    before { stub_voyage_credentials_key(nil) }

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

  describe "#perform with a Voyage credentials key configured" do
    let(:fake_embedding) { Array.new(1024) { 0.0 } }

    before do
      stub_voyage_credentials_key("vk_from_credentials")

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

    it "uses the credentials key as the bearer token" do
      described_class.new.perform(note.id)
      expect(WebMock).to(have_requested(:post, "https://api.voyageai.com/v1/embeddings").with { |req|
        req.headers["Authorization"] == "Bearer vk_from_credentials"
      })
    end
  end

  # Defensive: blank string (whitespace-only) credentials are treated
  # the same as nil by the gate.
  describe "#perform with a whitespace-only credentials key" do
    before { stub_voyage_credentials_key("   ") }

    it "does NOT call the Voyage API" do
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
