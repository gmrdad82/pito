require "rails_helper"

RSpec.describe Notes::EmbedJob, type: :job do
  let!(:project) { create(:project) }
  let!(:note) { create(:note, project: project, path: "alpha.md") }

  let(:tmp_root) { Dir.mktmpdir("pito-notes-embed-spec") }

  # Phase 29 — Unit A1. The Voyage API key moved out of the AppSetting
  # `voyage_api_key` column (dropped) and back into
  # `Rails.application.credentials.voyage.api_key` (flat block, shared
  # across environments). Specs stub the `:voyage` credentials block
  # instead of the column. The `voyage_index_project_notes` flag stays
  # on the AppSetting row.
  #
  # The full Voyage helper surface (including `stub_voyage_embed`) lives
  # in `spec/support/voyage.rb`; we still define the key-stub helper
  # locally because it predates the support module and is used purely
  # for the credential-presence branches below.
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

  # The Voyage gate ANDs the per-target `voyage_indexing_project_notes?`
  # flag with the `voyage_configured?` (credentials key present?) check.
  # BOTH must be true for the job to call Voyage; the job must
  # short-circuit cleanly when either is false.
  describe "#perform with voyage_indexing_project_notes? false (default)" do
    before do
      AppSetting.find_or_create_by!(key: "voyage_test") { |r| r.value = "x" }
        .update!(voyage_index_project_notes: false)
      stub_voyage_credentials_key("vk_from_credentials")
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
      record.update!(voyage_index_project_notes: true)
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

  # Defensive belt-and-suspenders: if the flag is on but no Voyage key
  # is configured in credentials, the job's dual check must still
  # short-circuit before any Voyage HTTP call.
  describe "#perform with voyage_indexing_project_notes? true but credentials key blank" do
    before do
      record = AppSetting.first || AppSetting.create!(key: "voyage_test", value: "x")
      record.update!(voyage_index_project_notes: true)
      stub_voyage_credentials_key(nil)
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

  # The flag must be on for the call to fire even when credentials carry
  # a key — `resolve_api_key` reads credentials, `voyage_configured?`
  # also reads credentials, but the per-target flag gates the whole
  # branch. Flag off → no Voyage call regardless of the key.
  describe "#perform when the credentials key is present but the flag is off" do
    before do
      record = AppSetting.first || AppSetting.create!(key: "voyage_test", value: "x")
      record.update!(voyage_index_project_notes: false)
      stub_voyage_credentials_key("voyage-key-from-creds")
    end

    it "does NOT call Voyage (the per-target flag gates the branch)" do
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
