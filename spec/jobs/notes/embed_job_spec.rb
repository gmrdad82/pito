require "rails_helper"

# Phase 34 (2026-05-18) — Notes no longer participate in the unified
# `/games` Meilisearch corpus. `Notes::EmbedJob#perform` is now a
# no-op: no Voyage AI HTTP call, no Meilisearch upsert, no write to
# `notes.embedding`. The job class survives only because
# `NoteSyncJob#enqueue_embed` still enqueues it (in case the corpus
# design reverts). See the job file's header comment for the full
# rationale.
#
# These specs encode the no-op contract:
#   - No HTTP to Voyage regardless of credentials state.
#   - No HTTP to Meilisearch.
#   - `notes.embedding` stays nil (we never write).
#   - Missing-note id is a no-op (no raise).
RSpec.describe Notes::EmbedJob, type: :job do
  let!(:project) { create(:project) }
  let!(:note) { create(:note, project: project, path: "alpha.md") }

  let(:tmp_root) { Dir.mktmpdir("pito-notes-embed-spec") }

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

    # If anything DOES leak through to Meilisearch, succeed silently
    # so the assertion (no request made) is the only signal that
    # matters.
    stub_request(:post, /127\.0\.0\.1:7727/).to_return(status: 200)
  end

  after do
    ENV["PITO_NOTES_PATH"] = @prev_root
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  describe "#perform (Phase 34 no-op)" do
    it "does NOT call the Voyage API when no credentials key is configured" do
      stub_voyage_credentials_key(nil)
      described_class.new.perform(note.id)
      expect(WebMock).not_to have_requested(:post, /api\.voyageai\.com/)
    end

    it "does NOT call the Voyage API even when a credentials key is configured" do
      stub_voyage_credentials_key("vk_from_credentials")
      described_class.new.perform(note.id)
      expect(WebMock).not_to have_requested(:post, /api\.voyageai\.com/)
    end

    it "does NOT call the Voyage API when the credentials key is whitespace-only" do
      stub_voyage_credentials_key("   ")
      described_class.new.perform(note.id)
      expect(WebMock).not_to have_requested(:post, /api\.voyageai\.com/)
    end

    it "does NOT upsert into the Meilisearch notes index" do
      stub_voyage_credentials_key("vk_from_credentials")
      described_class.new.perform(note.id)
      expect(WebMock).not_to have_requested(:post, %r{notes_test/documents})
    end

    it "leaves notes.embedding NULL" do
      stub_voyage_credentials_key("vk_from_credentials")
      described_class.new.perform(note.id)
      expect(note.reload.embedding).to be_nil
    end

    it "is a no-op when the note is missing" do
      expect {
        described_class.new.perform(999_999)
      }.not_to raise_error
    end
  end
end
