# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::CoverArt::Normalizer do
  let(:game) { create(:game, cover_image_id: "abc123", igdb_synced_at: 1.hour.ago) }
  subject(:normalizer) { described_class.new(game:) }

  describe "#call" do
    context "when cover_image_id is blank" do
      let(:game) { create(:game, cover_image_id: nil) }

      it "returns nil without touching the network" do
        expect(Net::HTTP).not_to receive(:start)
        expect(normalizer.call).to be_nil
      end
    end

    # Gate 1 — the attached master already carries the game's current
    # cover_image_id in its blob metadata: the CDN must not be queried at all.
    context "when the attached master matches the current cover_image_id (image_id gate)" do
      before do
        game.cover_art.attach(
          io:           StringIO.new("fake-jpeg-data"),
          filename:     "cover.jpg",
          content_type: "image/jpeg",
          metadata:     { "igdb_image_id" => "abc123" }
        )
      end

      it "returns the existing attachment without any network call" do
        expect(Net::HTTP).not_to receive(:start)
        result = normalizer.call
        expect(result).to be_a(ActiveStorage::Attached::One)
      end

      it "does not replace the blob" do
        original_blob_id = game.cover_art.blob.id
        normalizer.call
        expect(game.reload.cover_art.blob.id).to eq(original_blob_id)
      end

      it "does not touch the game" do
        before_touch = game.reload.updated_at
        normalizer.call
        expect(game.reload.updated_at).to eq(before_touch)
      end
    end

    # A NEW cover on IGDB means a NEW cover_image_id — the stale metadata must
    # not short-circuit; the new art is fetched and attached (touch = cache bust).
    context "when the game's cover_image_id changed since the master was attached" do
      let(:new_bytes) { "brand-new-cover-art" }

      before do
        game.cover_art.attach(
          io:           StringIO.new("old-cover-art"),
          filename:     "cover.jpg",
          content_type: "image/jpeg",
          metadata:     { "igdb_image_id" => "OLD-id" }
        )
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: new_bytes, headers: { "Content-Type" => "image/jpeg" })
      end

      it "fetches and attaches the new master" do
        original_blob_id = game.cover_art.blob.id
        normalizer.call
        expect(game.reload.cover_art.blob.id).not_to eq(original_blob_id)
        expect(game.cover_art.blob.checksum).to eq(Digest::MD5.base64digest(new_bytes))
      end

      it "stamps the new blob with the current image id" do
        normalizer.call
        expect(game.reload.cover_art.blob.metadata["igdb_image_id"]).to eq("abc123")
      end
    end

    context "when fetching from IGDB CDN" do
      let(:raw_bytes) { "fake-igdb-cover-bytes" }

      before do
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: raw_bytes, headers: { "Content-Type" => "image/jpeg" })
      end

      it "attaches the cover_art to the game" do
        normalizer.call
        expect(game.cover_art).to be_attached
      end

      it "returns the cover_art attachment" do
        result = normalizer.call
        expect(result).to be_a(ActiveStorage::Attached::One)
      end

      it "attaches the raw bytes unchanged — blob checksum matches the CDN bytes" do
        normalizer.call
        expect(game.cover_art.blob.checksum).to eq(Digest::MD5.base64digest(raw_bytes))
      end

      it "carries the source image id in the blob metadata (feeds gate 1)" do
        normalizer.call
        expect(game.cover_art.blob.metadata["igdb_image_id"]).to eq("abc123")
      end

      it "uses the SOURCE_SIZE URL segment (t_1080p)" do
        normalizer.call
        expect(WebMock).to have_requested(:get, /t_1080p\/abc123/)
      end
    end

    context "when IGDB CDN returns an error" do
      before do
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 404, body: "Not Found")
      end

      it "raises ExternalFetchFailed" do
        expect { normalizer.call }.to raise_error(Pito::Error::ExternalFetchFailed)
      end
    end

    # Gate 2 — legacy blob (attached before the metadata existed) whose bytes
    # still match the CDN: the image id is stamped IN PLACE. No new blob, no
    # attachment row, and crucially NO touch on the game (1.0.0 G25 — the
    # nightly attachment-touch marked ~all awaited games "updated").
    context "when a legacy metadata-less blob matches the CDN bytes (digest match)" do
      let(:raw_bytes) { "existing-cover-bytes-v1" }

      before do
        game.cover_art.attach(
          io:           StringIO.new(raw_bytes),
          filename:     "cover-#{game.id}.jpg",
          content_type: "image/jpeg"
        )
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: raw_bytes, headers: { "Content-Type" => "image/jpeg" })
      end

      it "does not create a new blob (digest-gate no-op)" do
        original_blob_id = game.cover_art.blob.id
        normalizer.call
        expect(game.reload.cover_art.blob.id).to eq(original_blob_id)
      end

      it "stamps the image id onto the existing blob (future runs skip the CDN)" do
        normalizer.call
        expect(game.reload.cover_art.blob.metadata["igdb_image_id"]).to eq("abc123")
      end

      it "does not touch the game" do
        before_touch = game.reload.updated_at
        normalizer.call
        expect(game.reload.updated_at).to eq(before_touch)
      end

      it "returns the existing attachment" do
        result = normalizer.call
        expect(result).to be_a(ActiveStorage::Attached::One)
      end
    end

    # Gate 2 — when bytes CHANGE the old blob must be replaced.
    context "when IGDB CDN returns updated bytes (digest mismatch)" do
      let(:original_bytes) { "cover-v1" }
      let(:updated_bytes)  { "cover-v2-different" }

      before do
        game.cover_art.attach(
          io:           StringIO.new(original_bytes),
          filename:     "cover-#{game.id}.jpg",
          content_type: "image/jpeg"
        )
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: updated_bytes, headers: { "Content-Type" => "image/jpeg" })
      end

      it "replaces the blob with the new bytes" do
        original_blob_id = game.cover_art.blob.id
        normalizer.call
        expect(game.reload.cover_art.blob.id).not_to eq(original_blob_id)
      end

      it "the new blob checksum matches the updated CDN bytes" do
        normalizer.call
        expect(game.reload.cover_art.blob.checksum).to eq(Digest::MD5.base64digest(updated_bytes))
      end
    end

    context "when force: true and the master is already current" do
      subject(:normalizer) { described_class.new(game:, force: true) }

      before do
        game.cover_art.attach(
          io:           StringIO.new("bytes"),
          filename:     "cover.jpg",
          content_type: "image/jpeg",
          metadata:     { "igdb_image_id" => "abc123" }
        )
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: "bytes", headers: { "Content-Type" => "image/jpeg" })
      end

      it "re-fetches from the CDN despite the current master" do
        normalizer.call
        expect(a_request(:get, /images\.igdb\.com.*abc123/)).to have_been_made
      end

      it "re-attaches even when digest matches (force bypasses both gates)" do
        original_blob_id = game.cover_art.blob.id
        normalizer.call
        expect(game.reload.cover_art.blob.id).not_to eq(original_blob_id)
      end
    end
  end

  describe "SOURCE_SIZE" do
    it "is t_1080p — the largest available IGDB CDN cover size" do
      expect(described_class::SOURCE_SIZE).to eq("t_1080p")
    end
  end
end
