# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Maintenance::ImageSweep do
  def attach_cover(game)
    game.cover_art.attach(io: StringIO.new("fake-bytes"), filename: "cover.jpg", content_type: "image/jpeg")
    game
  end

  describe ".blob_missing?" do
    it "is false for an unattached image" do
      expect(described_class.blob_missing?(create(:game).cover_art)).to be(false)
    end

    it "is false when the blob file exists on the service" do
      game = attach_cover(create(:game))
      expect(described_class.blob_missing?(game.cover_art)).to be(false)
    end

    it "is true when the attachment exists but the blob file is gone from disk" do
      game = attach_cover(create(:game))
      allow(game.cover_art.blob.service).to receive(:exist?).and_return(false)
      expect(described_class.blob_missing?(game.cover_art)).to be(true)
    end
  end

  describe ".missing" do
    it "collects only the games whose cover file is missing" do
      good = attach_cover(create(:game, title: "Present"))
      bad  = attach_cover(create(:game, title: "Gone"))
      allow_any_instance_of(ActiveStorage::Service::DiskService)
        .to receive(:exist?) { |_service, key| key != bad.cover_art.blob.key }

      games = described_class.missing[:games].map(&:id)
      expect(games).to include(bad.id)
      expect(games).not_to include(good.id)
    end
  end

  describe ".repair_game" do
    it "force-re-runs the cover normalizer (re-fetch from IGDB)" do
      game       = create(:game)
      normalizer = instance_double(Game::CoverArt::Normalizer, call: true)
      expect(Game::CoverArt::Normalizer).to receive(:new).with(game: game, force: true).and_return(normalizer)
      expect(described_class.repair_game(game)).to be(true)
    end

    it "returns false (and does not raise) when the normalizer fails" do
      game = create(:game)
      allow(Game::CoverArt::Normalizer).to receive(:new).and_raise(StandardError, "boom")
      expect(described_class.repair_game(game)).to be(false)
    end
  end

  describe ".repair_video" do
    it "skips a video whose connection needs reauth (counted as skipped, not fixed)" do
      connection = create(:youtube_connection, needs_reauth: true)
      channel    = create(:channel, youtube_connection: connection)
      video      = create(:video, channel: channel)
      expect(described_class.repair_video(video)).to be(false)
    end
  end
end
