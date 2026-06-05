# frozen_string_literal: true

require "rails_helper"

RSpec.describe Footage, type: :model do
  subject(:footage) { build(:footage) }

  describe "associations" do
    it { is_expected.to belong_to(:game).required }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:filename) }
    it { is_expected.to validate_uniqueness_of(:filename).scoped_to(:game_id) }

    it "is valid with a known orientation" do
      footage.orientation = "landscape"
      expect(footage).to be_valid
    end

    it "is valid with orientation nil" do
      footage.orientation = nil
      expect(footage).to be_valid
    end

    it "is invalid with an unknown orientation" do
      footage.orientation = "unknown"
      expect(footage).not_to be_valid
    end
  end

  describe "constants" do
    it "defines the expected orientation values" do
      expect(described_class::ORIENTATIONS).to eq(
        { landscape: "landscape", portrait: "portrait", square: "square" }
      )
    end
  end

  describe "#audio_track_count" do
    it "returns the length of audio_track_names" do
      footage.audio_track_names = %w[English Commentary]
      expect(footage.audio_track_count).to eq(2)
    end

    it "returns 0 when there are no audio tracks" do
      footage.audio_track_names = []
      expect(footage.audio_track_count).to eq(0)
    end
  end
end
