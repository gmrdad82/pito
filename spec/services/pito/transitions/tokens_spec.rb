require "rails_helper"

RSpec.describe Pito::Transitions::Tokens do
  describe "constants" do
    it "defines SCRAMBLE_DURATION_MS as an Integer" do
      expect(described_class::SCRAMBLE_DURATION_MS).to be_a(Integer)
    end

    it "defines SCRAMBLE_STAGGER_MS as an Integer" do
      expect(described_class::SCRAMBLE_STAGGER_MS).to be_a(Integer)
    end

    it "defines SCRAMBLE_FRAME_MS as an Integer" do
      expect(described_class::SCRAMBLE_FRAME_MS).to be_a(Integer)
    end

    it "defines COLOR_CROSSFADE_DURATION_MS as an Integer" do
      expect(described_class::COLOR_CROSSFADE_DURATION_MS).to be_a(Integer)
    end

    it "defines COLOR_CROSSFADE_EASING as a String" do
      expect(described_class::COLOR_CROSSFADE_EASING).to be_a(String)
    end

    it "defines SHIMMER_CYCLE_MS as an Integer" do
      expect(described_class::SHIMMER_CYCLE_MS).to be_a(Integer)
    end

    it "defines SHIMMER_GRADIENT_STOPS as a String" do
      expect(described_class::SHIMMER_GRADIENT_STOPS).to be_a(String)
    end

    it "defines DEBOUNCE_MS as an Integer" do
      expect(described_class::DEBOUNCE_MS).to be_a(Integer)
    end
  end

  describe "ALL" do
    it "has exactly 8 keys" do
      expect(described_class::ALL.keys.size).to eq(8)
    end

    it "is frozen" do
      expect(described_class::ALL).to be_frozen
    end

    it "includes every documented token" do
      expect(described_class::ALL.keys).to contain_exactly(
        :scramble_duration_ms,
        :scramble_stagger_ms,
        :scramble_frame_ms,
        :color_crossfade_duration_ms,
        :color_crossfade_easing,
        :shimmer_cycle_ms,
        :shimmer_gradient_stops,
        :debounce_ms
      )
    end

    it "maps keys to the constant values" do
      expect(described_class::ALL[:scramble_duration_ms]).to eq(described_class::SCRAMBLE_DURATION_MS)
      expect(described_class::ALL[:color_crossfade_easing]).to eq(described_class::COLOR_CROSSFADE_EASING)
      expect(described_class::ALL[:shimmer_gradient_stops]).to eq(described_class::SHIMMER_GRADIENT_STOPS)
    end
  end
end
