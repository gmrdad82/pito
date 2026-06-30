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

    context "when cover is already fresh (attached after igdb_synced_at)" do
      before do
        # Attach a stub cover file created AFTER igdb_synced_at
        game.cover_art.attach(
          io:           StringIO.new("fake-jpeg-data"),
          filename:     "cover.jpg",
          content_type: "image/jpeg"
        )
        # Simulate the attachment being newer than igdb_synced_at
        game.cover_art.attachment.update_columns(created_at: Time.current)
      end

      it "returns the existing attachment without re-fetching" do
        expect(Net::HTTP).not_to receive(:start)
        result = normalizer.call
        expect(result).to be_a(ActiveStorage::Attached::One)
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

    # Digest-gate: if the CDN returns the same bytes already stored, the blob
    # must NOT be replaced (no new blob, no new attachment row).
    context "when IGDB CDN returns the same bytes as the current attachment (digest match)" do
      let(:raw_bytes) { "existing-cover-bytes-v1" }

      before do
        game.cover_art.attach(
          io:           StringIO.new(raw_bytes),
          filename:     "cover-#{game.id}.jpg",
          content_type: "image/jpeg"
        )
        # Attachment older than igdb_synced_at so the mtime gate is bypassed
        game.cover_art.attachment.update_columns(created_at: 2.hours.ago)
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: raw_bytes, headers: { "Content-Type" => "image/jpeg" })
      end

      it "does not create a new blob (digest-gate no-op)" do
        original_blob_id = game.cover_art.blob.id
        normalizer.call
        expect(game.reload.cover_art.blob.id).to eq(original_blob_id)
      end

      it "returns the existing attachment" do
        result = normalizer.call
        expect(result).to be_a(ActiveStorage::Attached::One)
      end
    end

    # Digest-gate: when bytes CHANGE the old blob must be replaced.
    context "when IGDB CDN returns updated bytes (digest mismatch)" do
      let(:original_bytes) { "cover-v1" }
      let(:updated_bytes)  { "cover-v2-different" }

      before do
        game.cover_art.attach(
          io:           StringIO.new(original_bytes),
          filename:     "cover-#{game.id}.jpg",
          content_type: "image/jpeg"
        )
        game.cover_art.attachment.update_columns(created_at: 2.hours.ago)
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

    context "when force: true and the cover is already fresh" do
      subject(:normalizer) { described_class.new(game:, force: true) }

      before do
        game.cover_art.attach(io: StringIO.new("fake"), filename: "cover.jpg", content_type: "image/jpeg")
        game.cover_art.attachment.update_columns(created_at: Time.current)
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: "bytes", headers: { "Content-Type" => "image/jpeg" })
      end

      it "re-fetches from the CDN despite the fresh attachment" do
        normalizer.call
        expect(a_request(:get, /images\.igdb\.com.*abc123/)).to have_been_made
      end

      it "re-attaches even when digest matches (force bypasses digest gate)" do
        # Attach the same bytes so digest would match normally
        same_bytes = "bytes"
        game.cover_art.attach(io: StringIO.new(same_bytes), filename: "cover.jpg", content_type: "image/jpeg")
        game.cover_art.attachment.update_columns(created_at: Time.current)
        original_blob_id = game.cover_art.blob.id

        normalizer.call
        # force: true must replace the blob regardless of digest
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
