# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Maintenance::ImageSweep do
  def attach_cover(game)
    game.cover_art.attach(io: StringIO.new("fake-bytes"), filename: "cover.jpg", content_type: "image/jpeg")
    game
  end

  def attach_avatar(channel)
    channel.avatar.attach(io: StringIO.new("fake-bytes"), filename: "avatar.jpg", content_type: "image/jpeg")
    channel
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

    it "collects only the channels whose avatar file is missing" do
      good = attach_avatar(create(:channel, title: "Present"))
      bad  = attach_avatar(create(:channel, title: "Gone"))
      allow_any_instance_of(ActiveStorage::Service::DiskService)
        .to receive(:exist?) { |_service, key| key != bad.avatar.blob.key }

      channels = described_class.missing[:channels].map(&:id)
      expect(channels).to include(bad.id)
      expect(channels).not_to include(good.id)
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

  describe ".repair_channel" do
    it "skips a channel with no youtube_connection" do
      channel = create(:channel)  # no connection
      expect(described_class.repair_channel(channel)).to be(false)
    end

    it "skips a channel whose connection needs reauth" do
      connection = create(:youtube_connection, needs_reauth: true)
      channel    = create(:channel, youtube_connection: connection)
      expect(described_class.repair_channel(channel)).to be(false)
    end

    it "fetches the avatar_url via Client#fetch_channel and ingests it" do
      connection = create(:youtube_connection)
      channel    = create(:channel, youtube_connection: connection)
      client     = instance_double(Channel::Youtube::Client,
                                   fetch_channel: { avatar_url: "https://yt3.example.com/a.jpg" })
      ingest     = instance_double(Channel::Avatar::Ingest, call: true)

      expect(Channel::Youtube::Client).to receive(:new).with(connection).and_return(client)
      expect(Channel::Avatar::Ingest).to receive(:new)
        .with(channel: channel, source_url: "https://yt3.example.com/a.jpg")
        .and_return(ingest)

      expect(described_class.repair_channel(channel)).to be(true)
    end

    it "returns false when the avatar_url is blank" do
      connection = create(:youtube_connection)
      channel    = create(:channel, youtube_connection: connection)
      client     = instance_double(Channel::Youtube::Client, fetch_channel: { avatar_url: nil })

      allow(Channel::Youtube::Client).to receive(:new).with(connection).and_return(client)

      expect(described_class.repair_channel(channel)).to be(false)
    end

    it "returns false (and does not raise) when the client raises" do
      connection = create(:youtube_connection)
      channel    = create(:channel, youtube_connection: connection)
      allow(Channel::Youtube::Client).to receive(:new).and_raise(StandardError, "boom")
      expect(described_class.repair_channel(channel)).to be(false)
    end
  end
end
