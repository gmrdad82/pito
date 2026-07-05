# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Breakdown do
  let(:window) { Pito::Analytics::Window.for("28d", reference_date: Date.new(2026, 6, 8)) }
  let(:groups) { [] } # Primitives.fetch is stubbed; groups content is irrelevant

  def stub_primitives(report, data)
    allow(Pito::Analytics::Primitives).to receive(:fetch)
      .with(hash_including(report:)).and_return(data)
  end

  # ── :subscribed_status ────────────────────────────────────────────────────────

  describe ":subscribed_status" do
    it "returns UNSUBSCRIBED first then SUBSCRIBED as view shares" do
      stub_primitives("subscribed_status",
        "vidA" => [
          { "subscribed_status" => "SUBSCRIBED",   "views" => 300 },
          { "subscribed_status" => "UNSUBSCRIBED", "views" => 700 }
        ]
      )
      result = described_class.for(metric: :subscribed_status, groups:, window:)

      expect(result.map { |r| r[:key] }).to eq(%w[UNSUBSCRIBED SUBSCRIBED])
      expect(result.find { |r| r[:key] == "UNSUBSCRIBED" }[:pct]).to eq(70.0)
      expect(result.find { |r| r[:key] == "SUBSCRIBED" }[:pct]).to eq(30.0)
    end

    it "sums views across multiple subjects before computing shares" do
      # vidA: UNSUBSCRIBED=400; vidB: UNSUBSCRIBED=100, SUBSCRIBED=500
      # totals: UNSUBSCRIBED=500, SUBSCRIBED=500 → each 50%
      stub_primitives("subscribed_status",
        "vidA" => [ { "subscribed_status" => "UNSUBSCRIBED", "views" => 400 } ],
        "vidB" => [
          { "subscribed_status" => "UNSUBSCRIBED", "views" => 100 },
          { "subscribed_status" => "SUBSCRIBED",   "views" => 500 }
        ]
      )
      result = described_class.for(metric: :subscribed_status, groups:, window:)

      unsubbed = result.find { |r| r[:key] == "UNSUBSCRIBED" }
      subbed   = result.find { |r| r[:key] == "SUBSCRIBED" }
      expect(unsubbed[:pct]).to eq(50.0)
      expect(subbed[:pct]).to eq(50.0)
    end

    it "omits a status that is absent from the data" do
      stub_primitives("subscribed_status",
        "vidA" => [ { "subscribed_status" => "UNSUBSCRIBED", "views" => 1000 } ]
      )
      result = described_class.for(metric: :subscribed_status, groups:, window:)

      expect(result.map { |r| r[:key] }).to eq(%w[UNSUBSCRIBED])
    end

    it "returns [] when there is no data" do
      stub_primitives("subscribed_status", {})
      expect(described_class.for(metric: :subscribed_status, groups:, window:)).to eq([])
    end
  end

  # ── :devices ─────────────────────────────────────────────────────────────────

  describe ":devices" do
    it "folds TABLET into MOBILE and GAME_CONSOLE into TV" do
      # MOBILE=400, TABLET=100 → bucket MOBILE=500; DESKTOP=300; TV=150, GAME_CONSOLE=50 → bucket TV=200
      # total = 1000
      stub_primitives("device",
        "vidA" => [
          { "device_type" => "MOBILE",       "views" => 400 },
          { "device_type" => "TABLET",       "views" => 100 },
          { "device_type" => "DESKTOP",      "views" => 300 },
          { "device_type" => "TV",           "views" => 150 },
          { "device_type" => "GAME_CONSOLE", "views" => 50  }
        ]
      )
      result = described_class.for(metric: :devices, groups:, window:)

      mobile  = result.find { |r| r[:key] == "MOBILE" }
      desktop = result.find { |r| r[:key] == "DESKTOP" }
      tv      = result.find { |r| r[:key] == "TV" }

      expect(mobile[:pct]).to eq(50.0)  # 500 / 1000
      expect(desktop[:pct]).to eq(30.0) # 300 / 1000
      expect(tv[:pct]).to eq(20.0)      # 200 / 1000
    end

    it "emits buckets in MOBILE → DESKTOP → TV order regardless of input order" do
      stub_primitives("device",
        "vidA" => [
          { "device_type" => "TV",      "views" => 200 },
          { "device_type" => "DESKTOP", "views" => 300 },
          { "device_type" => "MOBILE",  "views" => 500 }
        ]
      )
      result = described_class.for(metric: :devices, groups:, window:)

      expect(result.map { |r| r[:key] }).to eq(%w[MOBILE DESKTOP TV])
    end

    it "excludes buckets with zero views" do
      stub_primitives("device",
        "vidA" => [ { "device_type" => "MOBILE", "views" => 1000 } ]
      )
      result = described_class.for(metric: :devices, groups:, window:)

      expect(result.map { |r| r[:key] }).to eq(%w[MOBILE])
    end

    it "returns [] when there is no data" do
      stub_primitives("device", {})
      expect(described_class.for(metric: :devices, groups:, window:)).to eq([])
    end
  end

  # ── :geography ───────────────────────────────────────────────────────────────

  describe ":geography" do
    it "returns the top 4 countries + the Other rollup when more than 5 exist (G78)" do
      # C7=700, C6=600, …, C1=100 → top-4 are C7,C6,C5,C4; C3..C1 roll up.
      rows = (1..7).map { |i| { "country" => "C#{i}", "views" => i * 100 } }.reverse
      stub_primitives("country", "vidA" => rows)

      result = described_class.for(metric: :geography, groups:, window:)

      expect(result.size).to eq(5)
      expect(result.map { |r| r[:key] }).to eq([ "C7", "C6", "C5", "C4", described_class::OTHER_KEY ])
    end

    it "totals exactly 100 with the long tail named, not dropped (G78)" do
      # 7 countries; grand = 2800. C7 = 700/2800 = 25.0, C6 = 21.4, C5 = 17.9,
      # C4 = 14.3 → top-4 = 78.6; Other carries the exact remainder 21.4.
      rows = (1..7).map { |i| { "country" => "C#{i}", "views" => i * 100 } }.reverse
      stub_primitives("country", "vidA" => rows)

      result = described_class.for(metric: :geography, groups:, window:)

      expect(result.first[:pct]).to eq(25.0)            # 700/2800 — denominator stays ALL countries
      expect(result.last[:pct]).to eq(21.4)             # 100 − top-4
      expect(result.sum { |r| r[:pct] }).to eq(100.0)
    end

    it "keeps 5 or fewer countries fully discrete (no rollup)" do
      rows = (1..5).map { |i| { "country" => "C#{i}", "views" => i * 100 } }.reverse
      stub_primitives("country", "vidA" => rows)

      result = described_class.for(metric: :geography, groups:, window:)

      expect(result.map { |r| r[:key] }).to eq(%w[C5 C4 C3 C2 C1])
      expect(result.map { |r| r[:key] }).not_to include(described_class::OTHER_KEY)
    end

    it "sums views across multiple subjects before ranking" do
      # US total = 300+200 = 500; ES = 200; DE = 100 → grand = 800
      # US pct = 500/800*100 = 62.5
      stub_primitives("country",
        "vidA" => [ { "country" => "US", "views" => 300 }, { "country" => "ES", "views" => 200 } ],
        "vidB" => [ { "country" => "US", "views" => 200 }, { "country" => "DE", "views" => 100 } ]
      )
      result = described_class.for(metric: :geography, groups:, window:)

      us = result.find { |r| r[:key] == "US" }
      expect(us[:pct]).to eq(62.5)
    end

    it "returns [] when there is no data" do
      stub_primitives("country", {})
      expect(described_class.for(metric: :geography, groups:, window:)).to eq([])
    end
  end

  # ── :gender ──────────────────────────────────────────────────────────────────

  describe ":gender" do
    it "sums viewer_percentage across subjects, renormalises to 100, and returns top 3 descending" do
      # vidA: male=50, female=30, gender_other=10
      # vidB: male=60, female=25, gender_other=5
      # totals: male=110, female=55, gender_other=15 → kept_sum=180
      # male pct  = 110/180*100 = 61.111… → 61.1
      # female pct = 55/180*100 = 30.555… → 30.6
      # other pct  = 15/180*100 = 8.333…  → 8.3
      stub_primitives("demographics",
        "vidA" => [
          { "gender" => "male",         "age_group" => "age25-34", "viewer_percentage" => 50.0 },
          { "gender" => "female",       "age_group" => "age25-34", "viewer_percentage" => 30.0 },
          { "gender" => "gender_other", "age_group" => "age25-34", "viewer_percentage" => 10.0 }
        ],
        "vidB" => [
          { "gender" => "male",         "age_group" => "age25-34", "viewer_percentage" => 60.0 },
          { "gender" => "female",       "age_group" => "age25-34", "viewer_percentage" => 25.0 },
          { "gender" => "gender_other", "age_group" => "age25-34", "viewer_percentage" => 5.0  }
        ]
      )
      result = described_class.for(metric: :gender, groups:, window:)

      expect(result.map { |r| r[:key] }).to eq(%w[male female gender_other])
      expect(result.find { |r| r[:key] == "male" }[:pct]).to eq(61.1)
      expect(result.find { |r| r[:key] == "female" }[:pct]).to eq(30.6)
      expect(result.find { |r| r[:key] == "gender_other" }[:pct]).to eq(8.3)
    end

    it "keeps 5 or fewer buckets discrete — the G78 rollup only engages beyond 5" do
      # 4 contrived buckets: all stay, honestly proportioned over the grand sum.
      stub_primitives("demographics",
        "vidA" => [
          { "gender" => "A", "viewer_percentage" => 40.0 },
          { "gender" => "B", "viewer_percentage" => 30.0 },
          { "gender" => "C", "viewer_percentage" => 20.0 },
          { "gender" => "D", "viewer_percentage" => 10.0 }
        ]
      )
      result = described_class.for(metric: :gender, groups:, window:)

      expect(result.map { |r| r[:key] }).to eq(%w[A B C D])
      expect(result.sum { |r| r[:pct] }).to eq(100.0)
    end

    it "returned pcts sum to 100 when all buckets are kept" do
      stub_primitives("demographics",
        "vidA" => [
          { "gender" => "male",         "viewer_percentage" => 60.0 },
          { "gender" => "female",       "viewer_percentage" => 30.0 },
          { "gender" => "gender_other", "viewer_percentage" => 10.0 }
        ]
      )
      result = described_class.for(metric: :gender, groups:, window:)

      expect(result.sum { |r| r[:pct] }).to eq(100.0)
    end

    it "returns [] when there is no data" do
      stub_primitives("demographics", {})
      expect(described_class.for(metric: :gender, groups:, window:)).to eq([])
    end
  end

  # ── :age ─────────────────────────────────────────────────────────────────────

  describe ":age" do
    it "returns top-4 age buckets + the Other rollup, totalling 100 (G78)" do
      # 6 age groups totalling 100.0 — shares are honest (over the grand sum,
      # no kept-bucket inflation): top-4 = 35+25+20+10; Other = 5+5 = 10.
      stub_primitives("demographics",
        "vidA" => [
          { "age_group" => "age25-34", "viewer_percentage" => 35.0 },
          { "age_group" => "age18-24", "viewer_percentage" => 25.0 },
          { "age_group" => "age35-44", "viewer_percentage" => 20.0 },
          { "age_group" => "age45-54", "viewer_percentage" => 10.0 },
          { "age_group" => "age55-64", "viewer_percentage" => 5.0  },
          { "age_group" => "age65-",   "viewer_percentage" => 5.0  }
        ]
      )
      result = described_class.for(metric: :age, groups:, window:)

      expect(result.size).to eq(5)
      expect(result.first[:key]).to eq("age25-34")
      expect(result.first[:pct]).to eq(35.0)
      expect(result.last).to eq({ key: described_class::OTHER_KEY, pct: 10.0 })
      expect(result.sum { |r| r[:pct] }).to eq(100.0)
    end

    it "sums viewer_percentage across multiple subjects before renormalising" do
      # vidA: age25-34=100; vidB: age18-24=100 → kept_sum=200; each 50%
      stub_primitives("demographics",
        "vidA" => [ { "age_group" => "age25-34", "viewer_percentage" => 100.0 } ],
        "vidB" => [ { "age_group" => "age18-24", "viewer_percentage" => 100.0 } ]
      )
      result = described_class.for(metric: :age, groups:, window:)

      expect(result.find { |r| r[:key] == "age25-34" }[:pct]).to eq(50.0)
      expect(result.find { |r| r[:key] == "age18-24" }[:pct]).to eq(50.0)
    end

    it "limits to at most 5 age groups" do
      rows = (1..7).map { |i| { "age_group" => "group#{i}", "viewer_percentage" => (8 - i) * 10.0 } }
      stub_primitives("demographics", "vidA" => rows)

      result = described_class.for(metric: :age, groups:, window:)

      expect(result.size).to eq(5)
    end

    it "returns [] when there is no data" do
      stub_primitives("demographics", {})
      expect(described_class.for(metric: :age, groups:, window:)).to eq([])
    end
  end

  # ── unknown metric / error handling ──────────────────────────────────────────

  describe "unknown metric" do
    it "returns [] for an unsupported metric symbol" do
      expect(described_class.for(metric: :foobar, groups:, window:)).to eq([])
    end
  end

  describe "error handling" do
    it "returns [] and logs a warning when Primitives.fetch raises" do
      allow(Pito::Analytics::Primitives).to receive(:fetch).and_raise(StandardError, "network timeout")
      expect(Rails.logger).to receive(:warn).with(/Analytics::Breakdown/)

      result = described_class.for(metric: :geography, groups:, window:)
      expect(result).to eq([])
    end
  end
end
