# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::MetricSelection do
  describe ".parse" do
    it "parses a `with` whitelist" do
      sel = described_class.parse("analyze vid #1 with views, subs")
      expect(sel.with).to eq(%i[views subs])
      expect(sel.without).to be_empty
    end

    it "parses a `without` exclude list (comms alias → canonical :comments)" do
      sel = described_class.parse("analyze vid #1 without comms")
      expect(sel.without).to eq(%i[comments])
      expect(sel.with).to be_empty
    end

    it "parses both with + without in one command" do
      sel = described_class.parse("analyze vid #1 with views without comms")
      expect(sel.with).to eq(%i[views])
      expect(sel.without).to eq(%i[comments])
    end

    it "resolves aliases (watched/geo/heatmap/gender/age/device/country)" do
      sel = described_class.parse("analyze vid #1 with watched, geo, heatmap, gender, age, device")
      expect(sel.with).to eq(%i[watched_hours geography day_of_week_heatmap demographics_gender demographics_age devices])
    end

    it "drops unknown tokens" do
      sel = described_class.parse("analyze vid #1 with views, bananas")
      expect(sel.with).to eq(%i[views])
    end

    it "is empty when there is no clause" do
      expect(described_class.parse("analyze vid #1")).not_to be_any
    end

    it "does not treat the 'with' inside 'without' as a with-clause" do
      sel = described_class.parse("analyze vid #1 without comms")
      expect(sel.with).to be_empty
    end
  end

  describe ".apply" do
    let(:metrics) { %i[views subs likes comments] }

    it "returns all metrics when the selection is empty (preserving order)" do
      expect(described_class.apply(metrics, described_class.parse("analyze vid #1"))).to eq(metrics)
    end

    it "whitelists with `with` (preserving the original order)" do
      sel = described_class.parse("analyze vid #1 with comms, views")
      expect(described_class.apply(metrics, sel)).to eq(%i[views comments])
    end

    it "excludes with `without`" do
      sel = described_class.parse("analyze vid #1 without subs, comms")
      expect(described_class.apply(metrics, sel)).to eq(%i[views likes])
    end
  end

  describe ".from_lists (marker round-trip)" do
    it "rebuilds a selection from stored string arrays, dropping unknowns" do
      sel = described_class.from_lists(%w[views nope], %w[comms])
      expect(sel.with).to eq(%i[views])
      expect(sel.without).to eq(%i[comments])
    end
  end
end
