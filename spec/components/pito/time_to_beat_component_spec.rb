# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::TimeToBeatComponent do
  let(:game) do
    build_stubbed(:game,
                  ttb_main_seconds:          50 * 3600,
                  ttb_extras_seconds:        100 * 3600,
                  ttb_completionist_seconds: 200 * 3600)
  end

  describe "SAMPLE_HOURS" do
    it "is the documented triplet" do
      expect(described_class::SAMPLE_HOURS).to eq(main: 31, extras: 71, completionist: 124)
    end
  end

  describe "PILLAR_KEYS" do
    it "is [:main, :extras, :completionist]" do
      expect(described_class::PILLAR_KEYS).to eq(%i[main extras completionist])
    end
  end

  describe "#hours" do
    it "reads IGDB seconds from the game" do
      comp = described_class.new(game: game)
      expect(comp.hours).to eq(main: 50, extras: 100, completionist: 200)
    end

    it "falls back to SAMPLE_HOURS when all ttb seconds are zero" do
      bare = build_stubbed(:game,
                            ttb_main_seconds: 0,
                            ttb_extras_seconds: 0,
                            ttb_completionist_seconds: 0)
      comp = described_class.new(game: bare)
      expect(comp.hours).to eq(described_class::SAMPLE_HOURS)
    end

    it "falls back to SAMPLE_HOURS when all ttb seconds are nil" do
      bare = build_stubbed(:game,
                            ttb_main_seconds: nil,
                            ttb_extras_seconds: nil,
                            ttb_completionist_seconds: nil)
      comp = described_class.new(game: bare)
      expect(comp.hours).to eq(described_class::SAMPLE_HOURS)
    end

    it "lets an explicit hours kwarg trump both game and sample" do
      bare = build_stubbed(:game, ttb_main_seconds: 0, ttb_extras_seconds: 0, ttb_completionist_seconds: 0)
      comp = described_class.new(game: bare, hours: { main: 7, extras: 14, completionist: 21 })
      expect(comp.hours).to eq(main: 7, extras: 14, completionist: 21)
    end
  end

  describe "#max_x" do
    it "is completionist * 1.05 rounded" do
      comp = described_class.new(game: game, footage_hours: 50)
      # max(200, 50, 10) = 200; 200 * 1.05 = 210
      expect(comp.max_x).to eq(210)
    end
  end

  describe "#position" do
    it "projects a value onto the 0..100 axis" do
      comp = described_class.new(game: game, footage_hours: 50)
      # main 50 / 210 = 23.81 %
      expect(comp.position(50)).to be_within(0.01).of(23.810)
    end

    it "clamps to 100" do
      comp = described_class.new(game: game)
      expect(comp.position(999)).to eq(100.0)
    end
  end

  describe "#label_for" do
    it "formats a positive pillar as 'Nh'" do
      comp = described_class.new(game: game)
      expect(comp.label_for(:main)).to include("50")
    end

    it "returns em-dash for zero" do
      comp = described_class.new(game: game, hours: { main: 0, extras: 10, completionist: 20 })
      expect(comp.label_for(:main)).to eq("—")
    end
  end

  describe "#tick_overlays" do
    it "returns 4 entries (3 pillars + footage)" do
      comp = described_class.new(game: game, footage_hours: 50)
      expect(comp.tick_overlays.length).to eq(4)
    end

    it "includes the correct keys" do
      comp = described_class.new(game: game, footage_hours: 50)
      keys = comp.tick_overlays.map { |t| t[:key] }
      expect(keys).to eq(%i[main extras completionist footage])
    end
  end

  describe "#pillar_label_data" do
    it "returns 3 entries in pillar key order" do
      comp = described_class.new(game: game)
      keys = comp.pillar_label_data.map { |d| d[:key] }
      expect(keys).to eq(%i[main extras completionist])
    end

    it "nudges colliding labels apart" do
      # main 31h / 775 = 4.0 %, extras 71h / 775 = 9.16 % → gap < 10 % → collision
      crimson = build_stubbed(:game,
                                ttb_main_seconds:          31  * 3600,
                                ttb_extras_seconds:        71  * 3600,
                                ttb_completionist_seconds: 738 * 3600)
      comp = described_class.new(game: crimson, footage_hours: 0)
      data = comp.pillar_label_data

      expect(data[0][:nudge]).to eq(:left)
      expect(data[1][:nudge]).to eq(:right)
      expect(data[2][:nudge]).to be_nil
    end
  end

  describe "#gradient_break_positions" do
    it "returns p1..p6" do
      comp = described_class.new(game: game, footage_hours: 0)
      breaks = comp.gradient_break_positions
      expect(breaks.keys).to eq(%i[p1 p2 p3 p4 p5 p6])
      # All values should be percentage strings ending in '%'
      breaks.each_value do |v|
        expect(v).to end_with("%")
      end
    end
  end
end
