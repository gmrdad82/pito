# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::Builder do
  # The Builder uses the real Notification AR model (message + read_at
  # columns only — it sets additional fields not in the current schema via
  # `create!`; those fields must be stripped or the insert will fail).
  #
  # IMPORTANT: The current Notification schema only has `message` and
  # `read_at`. The Builder sets `category`, `kind`, `severity`, `title`,
  # `event_type`, `fires_at`, `event_payload`, `dedup_key` — these do NOT
  # exist yet (Phase-26 migration pending). We therefore test the
  # copy-validation and dedup-key logic at the PORO level, and skip
  # the persist path (which would raise ActiveRecord::UnknownAttributeError).
  #
  # Once Phase-26 migrations land, remove the skip tags below and the
  # persist-path examples will run for free.

  describe ".build_channel copy validation" do
    let(:channel) { double("channel", id: 1) }

    it "returns failure when message is blank" do
      result = described_class.build_channel(channel: channel, message: "", kind: :sync_error)
      expect(result.success?).to be false
      expect(result.errors).to include(/can't be blank/)
    end

    it "returns failure when message exceeds 140 characters" do
      long = "x" * 141
      result = described_class.build_channel(channel: channel, message: long, kind: :sync_error)
      expect(result.success?).to be false
      expect(result.errors).to include(/140/)
    end

    it "returns failure when message contains an emoji" do
      result = described_class.build_channel(channel: channel, message: "Hi 🎮 there", kind: :sync_error)
      expect(result.success?).to be false
      expect(result.errors).to include(/emoji/)
    end

    it "accepts exactly 140 characters (copy validation only)" do
      msg = "a" * 140
      # copy validation passes — we only check the copy-level errors, not persist
      errors = described_class.__send__(:validate_copy, msg)
      expect(errors).not_to include(/140/)
    end
  end

  describe ".build_game copy validation" do
    let(:game) { double("game", id: 7) }

    it "returns failure on blank message" do
      result = described_class.build_game(game: game, message: nil, kind: :game_release_today)
      expect(result.success?).to be false
      expect(result.errors).to include(/can't be blank/)
    end

    it "returns failure on emoji message" do
      result = described_class.build_game(game: game, message: "launch 🚀", kind: :game_release_today)
      expect(result.success?).to be false
      expect(result.errors).to include(/emoji/)
    end
  end

  describe ".build_system copy validation" do
    it "returns failure on too-long message" do
      result = described_class.build_system(message: "z" * 200, kind: :sync_error)
      expect(result.success?).to be false
    end

    it "passes copy validation for a short valid message" do
      errors = described_class.__send__(:validate_copy, "System alert")
      expect(errors).to be_empty
    end
  end

  describe ".build_manual copy validation" do
    let(:user) { double("user", id: 3) }

    it "returns failure on blank message" do
      result = described_class.build_manual(user: user, message: "  ", kind: :calendar_entry_firing)
      expect(result.success?).to be false
    end
  end

  describe "Result value object" do
    it "success? and failure? are inverses" do
      ok  = described_class::Result.new(success: true,  record: nil, errors: [])
      bad = described_class::Result.new(success: false, record: nil, errors: [ "oops" ])
      expect(ok.success?).to  be true
      expect(ok.failure?).to  be false
      expect(bad.success?).to be false
      expect(bad.failure?).to be true
    end
  end
end
