# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievements::Label do
  describe ".for" do
    # ── Plural default (no count / count != 1) ────────────────────────────────

    it "returns 'Subs' for 'subs' (plural default)" do
      expect(described_class.for("subs")).to eq("Subs")
    end

    it "returns 'Subs' for 'subs_gained' (plural default)" do
      expect(described_class.for("subs_gained")).to eq("Subs")
    end

    it "returns 'Views' for 'views' (plural default)" do
      expect(described_class.for("views")).to eq("Views")
    end

    it "returns 'Clocks' for 'watched_hours' (plural default)" do
      expect(described_class.for("watched_hours")).to eq("Clocks")
    end

    it "returns 'Likes' for 'likes' (plural default)" do
      expect(described_class.for("likes")).to eq("Likes")
    end

    it "returns 'Comms' for 'comments' (plural default)" do
      expect(described_class.for("comments")).to eq("Comms")
    end

    # ── Singular (count: 1) ───────────────────────────────────────────────────

    it "returns 'Sub' for 'subs' when count is 1" do
      expect(described_class.for("subs", count: 1)).to eq("Sub")
    end

    it "returns 'Sub' for 'subs_gained' when count is 1" do
      expect(described_class.for("subs_gained", count: 1)).to eq("Sub")
    end

    it "returns 'View' for 'views' when count is 1" do
      expect(described_class.for("views", count: 1)).to eq("View")
    end

    it "returns 'Clock' for 'watched_hours' when count is 1" do
      expect(described_class.for("watched_hours", count: 1)).to eq("Clock")
    end

    it "returns 'Like' for 'likes' when count is 1" do
      expect(described_class.for("likes", count: 1)).to eq("Like")
    end

    it "returns 'Comm' for 'comments' when count is 1" do
      expect(described_class.for("comments", count: 1)).to eq("Comm")
    end

    # ── Plural with explicit count > 1 ───────────────────────────────────────

    it "returns 'Views' for 'views' when count is 2" do
      expect(described_class.for("views", count: 2)).to eq("Views")
    end

    it "returns 'Subs' for 'subs' when count is 1_000" do
      expect(described_class.for("subs", count: 1_000)).to eq("Subs")
    end

    # ── nil count is the same as omitted (plural) ─────────────────────────────

    it "returns plural when count is nil (explicit)" do
      expect(described_class.for("views", count: nil)).to eq("Views")
    end

    # ── Symbol arguments ──────────────────────────────────────────────────────

    it "accepts symbol arguments (plural)" do
      expect(described_class.for(:views)).to eq("Views")
      expect(described_class.for(:watched_hours)).to eq("Clocks")
    end

    it "accepts symbol arguments (singular)" do
      expect(described_class.for(:views, count: 1)).to eq("View")
      expect(described_class.for(:watched_hours, count: 1)).to eq("Clock")
    end

    # ── Resolves via Pito::Copy ───────────────────────────────────────────────

    it "resolves all 6 metrics via Pito::Copy without raising" do
      %w[subs subs_gained views watched_hours likes comments].each do |metric|
        expect { described_class.for(metric) }.not_to raise_error
        expect { described_class.for(metric, count: 1) }.not_to raise_error
      end
    end

    # ── Error cases ───────────────────────────────────────────────────────────

    it "raises KeyError for unknown metrics" do
      expect { described_class.for("unknown_metric") }.to raise_error(KeyError)
    end

    it "raises KeyError for empty string" do
      expect { described_class.for("") }.to raise_error(KeyError)
    end
  end

  describe ".badge" do
    # ── Badge word map (full title-case word displayed on the badge face) ─────

    it "returns 'Subs' for 'subs'" do
      expect(described_class.badge("subs")).to eq("Subs")
    end

    it "returns 'Subs' for 'subs_gained'" do
      expect(described_class.badge("subs_gained")).to eq("Subs")
    end

    it "returns 'Views' for 'views'" do
      expect(described_class.badge("views")).to eq("Views")
    end

    it "returns 'Watched' for 'watched_hours' (distinct from the plural label 'Clocks')" do
      expect(described_class.badge("watched_hours")).to eq("Watched")
    end

    it "returns 'Likes' for 'likes'" do
      expect(described_class.badge("likes")).to eq("Likes")
    end

    it "returns 'Comms' for 'comments'" do
      expect(described_class.badge("comments")).to eq("Comms")
    end

    # ── Symbol arguments ──────────────────────────────────────────────────────

    it "accepts symbol arguments" do
      expect(described_class.badge(:views)).to eq("Views")
      expect(described_class.badge(:watched_hours)).to eq("Watched")
    end

    # ── All 6 metrics resolve without raising ─────────────────────────────────

    it "resolves all 6 metrics via Pito::Copy without raising" do
      %w[subs subs_gained views watched_hours likes comments].each do |metric|
        expect { described_class.badge(metric) }.not_to raise_error
      end
    end

    # ── Error cases ───────────────────────────────────────────────────────────

    it "raises KeyError for unknown metrics" do
      expect { described_class.badge("unknown_metric") }.to raise_error(KeyError)
    end
  end

  describe ".abbr" do
    # ── Abbreviation map ─────────────────────────────────────────────────────

    it "returns 'V' for 'views'" do
      expect(described_class.abbr("views")).to eq("V")
    end

    it "returns 'L' for 'likes'" do
      expect(described_class.abbr("likes")).to eq("L")
    end

    it "returns 'C' for 'comments'" do
      expect(described_class.abbr("comments")).to eq("C")
    end

    it "returns 'W' for 'watched_hours'" do
      expect(described_class.abbr("watched_hours")).to eq("W")
    end

    it "returns 'S' for 'subs'" do
      expect(described_class.abbr("subs")).to eq("S")
    end

    it "returns 'S' for 'subs_gained'" do
      expect(described_class.abbr("subs_gained")).to eq("S")
    end

    # ── Symbol arguments ──────────────────────────────────────────────────────

    it "accepts symbol arguments" do
      expect(described_class.abbr(:views)).to eq("V")
      expect(described_class.abbr(:watched_hours)).to eq("W")
    end

    # ── All 6 metrics resolve without raising ─────────────────────────────────

    it "resolves all 6 metrics via Pito::Copy without raising" do
      %w[subs subs_gained views watched_hours likes comments].each do |metric|
        expect { described_class.abbr(metric) }.not_to raise_error
      end
    end

    # ── Abbreviations are single characters ───────────────────────────────────

    it "returns a single-character string for every metric" do
      %w[subs subs_gained views watched_hours likes comments].each do |metric|
        expect(described_class.abbr(metric).length).to eq(1),
          "Expected single char for #{metric}, got #{described_class.abbr(metric).inspect}"
      end
    end

    # ── Error cases ───────────────────────────────────────────────────────────

    it "raises KeyError for unknown metrics" do
      expect { described_class.abbr("unknown_metric") }.to raise_error(KeyError)
    end
  end
end
