require "rails_helper"

RSpec.describe Pito::Themes::Mix do
  describe ".call" do
    it "returns a at t=0.0" do
      expect(described_class.call("#000000", "#ffffff", 0.0)).to eq("#000000")
    end

    it "returns b at t=1.0" do
      expect(described_class.call("#000000", "#ffffff", 1.0)).to eq("#ffffff")
    end

    it "returns the midpoint at t=0.5" do
      result = described_class.call("#000000", "#ffffff", 0.5)
      expect(result).to eq("#808080")
    end

    it "blends a known midpoint correctly" do
      # mix("#1a1b26", "#c0caf5", 0.06)
      # R: 0x1a + (0xc0 - 0x1a) * 0.06 = 26 + 162 * 0.06 = 26 + 9.72 → round = 36 = 0x24
      # G: 0x1b + (0xca - 0x1b) * 0.06 = 27 + 175 * 0.06 = 27 + 10.5 → round = 38 = 0x26? No:
      # Actually let's compute inline:
      bg = "#1a1b26"
      fg = "#c0caf5"
      result = described_class.call(bg, fg, 0.06)
      # Verify it's a valid hex colour
      expect(result).to match(/\A#[0-9a-f]{6}\z/)
      # Verify R channel specifically: 0x1a=26, 0xc0=192, diff=166, *0.06=9.96→10, 26+10=36=0x24
      expect(result[1..2]).to eq("24")
    end

    it "raises ArgumentError for t outside 0-1" do
      expect { described_class.call("#000000", "#ffffff", 1.1) }.to raise_error(ArgumentError)
      expect { described_class.call("#000000", "#ffffff", -0.1) }.to raise_error(ArgumentError)
    end

    it "handles t=0.4 blend correctly" do
      # mix("#aaaaaa", "#bbbbbb", 0.4)
      # 0xaa=170, 0xbb=187, diff=17, 17*0.4=6.8→7, 170+7=177=0xb1
      result = described_class.call("#aaaaaa", "#bbbbbb", 0.4)
      expect(result).to eq("#b1b1b1")
    end
  end
end
