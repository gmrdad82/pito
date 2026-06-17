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
      before do
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: "fake-jpeg-bytes", headers: { "Content-Type" => "image/jpeg" })
        # Stub vips processing — we test image arithmetic separately.
        # Here we only care that the CDN fetch + ActiveStorage attach path works.
        allow(normalizer).to receive(:normalize).and_return(double("vips_img"))
        allow(normalizer).to receive(:attach_to_game) do |_img|
          game.cover_art.attach(
            io:           StringIO.new("processed-jpeg"),
            filename:     "cover.jpg",
            content_type: "image/jpeg"
          )
        end
      end

      it "attaches the cover_art to the game" do
        normalizer.call
        expect(game.cover_art).to be_attached
      end

      it "returns the cover_art attachment" do
        result = normalizer.call
        expect(result).to be_a(ActiveStorage::Attached::One)
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

    context "when force: true and the cover is already fresh" do
      subject(:normalizer) { described_class.new(game:, force: true) }

      before do
        game.cover_art.attach(io: StringIO.new("fake"), filename: "cover.jpg", content_type: "image/jpeg")
        game.cover_art.attachment.update_columns(created_at: Time.current)
        stub_request(:get, /images\.igdb\.com.*abc123/)
          .to_return(status: 200, body: "bytes", headers: { "Content-Type" => "image/jpeg" })
        allow(normalizer).to receive(:normalize).and_return(double("vips_img"))
        allow(normalizer).to receive(:attach_to_game)
      end

      it "re-fetches from the CDN despite the fresh attachment" do
        normalizer.call
        expect(a_request(:get, /images\.igdb\.com.*abc123/)).to have_been_made
      end
    end
  end

  describe "master dimensions" do
    it "are 374×499 (3:4) — the 374px game-detail cover (two 180px covers + gap)" do
      expect(described_class::MASTER_W).to eq(374)
      expect(described_class::MASTER_H).to eq(499)
    end
  end
end
