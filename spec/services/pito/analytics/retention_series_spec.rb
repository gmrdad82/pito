# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::RetentionSeries do
  let(:conversation) { Conversation.singleton }
  let(:channel)      { create(:channel, :on_connection) }
  let(:window)       { Pito::Analytics::Window.for("7d", reference_date: Date.new(2026, 6, 28)) }

  # A minimal retention curve (21 points, 0→1 ratio, descending watch ratio).
  def retention_curve(length: 21, start_ratio: 0.98)
    length.times.map do |i|
      {
        elapsed_video_time_ratio: i.to_f / (length - 1),
        audience_watch_ratio:     [ start_ratio - (i * 0.04), 0.0 ].max,
        relative_retention_performance: 1.0
      }
    end
  end

  # Stub ALL external HTTP so specs never hit the network.
  before { stub_request(:any, /youtube/).to_return(status: 200, body: "{}") }

  # ── expand_to_triples ────────────────────────────────────────────────────────

  describe ".expand_to_triples" do
    context "with vid/game-level groups (per-video IDs in subjects)" do
      it "returns one triple per video with views from the scalars primitives" do
        vid = create(:video, channel:)
        groups = [ [ channel, [ vid.youtube_video_id ] ] ]

        allow(Pito::Analytics::Primitives).to receive(:fetch)
          .with(hash_including(report: "scalars"))
          .and_return(vid.youtube_video_id => { "views" => 1234 })

        triples = described_class.expand_to_triples(groups:, window:)
        expect(triples.size).to eq(1)
        expect(triples.first).to eq([ channel, vid.youtube_video_id, 1234 ])
      end

      it "uses 0 views when scalars are missing for a video" do
        vid = create(:video, channel:)
        groups = [ [ channel, [ vid.youtube_video_id ] ] ]

        allow(Pito::Analytics::Primitives).to receive(:fetch)
          .with(hash_including(report: "scalars")).and_return({})

        triples = described_class.expand_to_triples(groups:, window:)
        expect(triples.first[2]).to eq(0)
      end
    end

    context "with channel-level groups (:channel subject)" do
      it "expands to the channel's videos (up to CHANNEL_VIDEO_LIMIT)" do
        create_list(:video, 3, channel:)
        groups = [ [ channel, :channel ] ]

        allow(Pito::Analytics::Primitives).to receive(:fetch)
          .with(hash_including(report: "scalars")).and_return({})

        triples = described_class.expand_to_triples(groups:, window:)
        expect(triples.size).to eq(3)
        expect(triples.map { |t| t[0] }).to all(eq(channel))
      end

      it "returns [] when the channel has no videos" do
        groups = [ [ channel, :channel ] ]
        allow(Pito::Analytics::Primitives).to receive(:fetch)
          .with(hash_including(report: "scalars")).and_return({})
        expect(described_class.expand_to_triples(groups:, window:)).to eq([])
      end
    end
  end

  # ── parse_curve ──────────────────────────────────────────────────────────────

  describe ".parse_curve" do
    it "extracts audienceWatchRatio from symbol-keyed hashes (fresh API)" do
      data = [
        { elapsed_video_time_ratio: 0.0,  audience_watch_ratio: 0.98 },
        { elapsed_video_time_ratio: 0.5,  audience_watch_ratio: 0.60 },
        { elapsed_video_time_ratio: 1.0,  audience_watch_ratio: 0.20 }
      ]
      result = described_class.parse_curve(data)
      expect(result.curve).to eq([ 0.98, 0.60, 0.20 ])
    end

    it "extracts audienceWatchRatio from string-keyed hashes (from DB cache)" do
      data = [
        { "elapsed_video_time_ratio" => 0.0, "audience_watch_ratio" => 0.95 },
        { "elapsed_video_time_ratio" => 1.0, "audience_watch_ratio" => 0.10 }
      ]
      result = described_class.parse_curve(data)
      expect(result.curve).to eq([ 0.95, 0.10 ])
    end

    it "returns empty arrays for nil or non-array input" do
      expect(described_class.parse_curve(nil).curve).to eq([])
      expect(described_class.parse_curve({}).curve).to  eq([])
    end

    it "skips rows missing the audienceWatchRatio key" do
      data = [
        { "elapsed_video_time_ratio" => 0.0 },
        { "audience_watch_ratio" => 0.5 }
      ]
      result = described_class.parse_curve(data)
      expect(result.curve).to eq([ 0.5 ])
    end

    it "parses relativeRetentionPerformance from symbol-keyed hashes" do
      data = [
        { audience_watch_ratio: 0.9, relative_retention_performance: 0.6 },
        { audience_watch_ratio: 0.7, relative_retention_performance: 0.4 },
        { audience_watch_ratio: 0.5, relative_retention_performance: 0.5 }
      ]
      result = described_class.parse_curve(data)
      expect(result.rel_performance).to eq([ 0.6, 0.4, 0.5 ])
    end

    it "parses relativeRetentionPerformance from string-keyed hashes (DB cache)" do
      data = [
        { "audience_watch_ratio" => 0.8, "relative_retention_performance" => 0.55 },
        { "audience_watch_ratio" => 0.6, "relative_retention_performance" => 0.45 }
      ]
      result = described_class.parse_curve(data)
      expect(result.rel_performance).to eq([ 0.55, 0.45 ])
    end

    it "returns empty rel_performance when the column is absent" do
      data = [
        { "audience_watch_ratio" => 0.8 },
        { "audience_watch_ratio" => 0.6 }
      ]
      result = described_class.parse_curve(data)
      expect(result.rel_performance).to eq([])
    end
  end

  # ── views_weighted_average ───────────────────────────────────────────────────

  describe ".views_weighted_average" do
    it "computes a simple equal-weight average when all weights are 0" do
      curves  = { "a" => [ 0.9, 0.5 ], "b" => [ 0.7, 0.3 ] }
      weights = { "a" => 0, "b" => 0 }
      result  = described_class.views_weighted_average(curves, weights)
      expect(result[0]).to be_within(0.001).of(0.8)
      expect(result[1]).to be_within(0.001).of(0.4)
    end

    it "weights by views correctly (higher-view video dominates)" do
      # vid A: 900 views, ratio [0.9, 0.5];  vid B: 100 views, ratio [0.1, 0.1]
      curves  = { "a" => [ 0.9, 0.5 ], "b" => [ 0.1, 0.1 ] }
      weights = { "a" => 900, "b" => 100 }
      result  = described_class.views_weighted_average(curves, weights)
      # Expected: 0.9×0.9 + 0.1×0.1 = 0.81+0.01 = 0.82
      expect(result[0]).to be_within(0.001).of(0.82)
    end

    it "returns [] for empty curves" do
      expect(described_class.views_weighted_average({}, {})).to eq([])
    end

    it "handles a single-video scope (trivial average)" do
      curves  = { "a" => [ 0.98, 0.70, 0.40 ] }
      weights = { "a" => 500 }
      result  = described_class.views_weighted_average(curves, weights)
      expect(result).to eq([ 0.98, 0.70, 0.40 ])
    end
  end

  # ── interpolate_curve ────────────────────────────────────────────────────────

  describe ".interpolate_curve" do
    it "returns the curve unchanged when sizes match" do
      c = [ 0.9, 0.7, 0.5 ]
      expect(described_class.interpolate_curve(c, 3)).to eq(c)
    end

    it "interpolates a 3-point curve to 5 points" do
      c = [ 1.0, 0.6, 0.2 ]
      result = described_class.interpolate_curve(c, 5)
      expect(result.size).to eq(5)
      expect(result.first).to be_within(0.001).of(1.0)
      expect(result.last).to  be_within(0.001).of(0.2)
      # Midpoint should be ~0.6
      expect(result[2]).to be_within(0.001).of(0.6)
    end

    it "returns a constant array for a single-point curve" do
      result = described_class.interpolate_curve([ 0.75 ], 4)
      expect(result).to all(be_within(0.001).of(0.75))
    end
  end

  # ── views_weighted_benchmark ─────────────────────────────────────────────────

  describe ".views_weighted_benchmark" do
    it "returns nil for empty benchmarks" do
      expect(described_class.views_weighted_benchmark({}, {})).to be_nil
    end

    it "returns nil when all rel_performance arrays are empty" do
      expect(described_class.views_weighted_benchmark({ "a" => [] }, { "a" => 100 })).to be_nil
    end

    it "computes equal-weight mean when all weights are 0" do
      benchmarks = { "a" => [ 0.6, 0.7 ], "b" => [ 0.4, 0.5 ] }
      weights    = { "a" => 0, "b" => 0 }
      result = described_class.views_weighted_benchmark(benchmarks, weights)
      # Equal weight: mean_a = 0.65, mean_b = 0.45, weighted = 0.55
      expect(result).to be_within(0.01).of(0.55)
    end

    it "weights by views (higher-view video dominates)" do
      benchmarks = { "a" => [ 0.8 ], "b" => [ 0.2 ] }
      weights    = { "a" => 900, "b" => 100 }
      result = described_class.views_weighted_benchmark(benchmarks, weights)
      # 0.9×0.8 + 0.1×0.2 = 0.72 + 0.02 = 0.74
      expect(result).to be_within(0.01).of(0.74)
    end

    it "skips videos with empty rel_performance arrays" do
      benchmarks = { "a" => [ 0.6 ], "b" => [] }
      weights    = { "a" => 500, "b" => 500 }
      result = described_class.views_weighted_benchmark(benchmarks, weights)
      # Only "a" counts; it's the only non-empty one
      expect(result).to be_within(0.01).of(0.6)
    end
  end

  # ── benchmark_word ───────────────────────────────────────────────────────────

  describe ".benchmark_word" do
    it "returns 'above average' for values >= 0.55" do
      expect(described_class.benchmark_word(0.55)).to eq("above average")
      expect(described_class.benchmark_word(0.70)).to eq("above average")
      expect(described_class.benchmark_word(1.0)).to  eq("above average")
    end

    it "returns 'below average' for values <= 0.45" do
      expect(described_class.benchmark_word(0.45)).to eq("below average")
      expect(described_class.benchmark_word(0.30)).to eq("below average")
      expect(described_class.benchmark_word(0.0)).to  eq("below average")
    end

    it "returns 'typical' for values between 0.45 and 0.55 exclusive" do
      expect(described_class.benchmark_word(0.50)).to eq("typical")
      expect(described_class.benchmark_word(0.46)).to eq("typical")
      expect(described_class.benchmark_word(0.54)).to eq("typical")
    end

    it "returns 'typical' for nil input" do
      expect(described_class.benchmark_word(nil)).to eq("typical")
    end
  end

  # ── at_mark_pct ──────────────────────────────────────────────────────────────

  describe ".at_mark_pct" do
    it "returns 0 for an empty series" do
      expect(described_class.at_mark_pct([], 20.0)).to eq(0)
    end

    it "returns the first element for a single-point series" do
      expect(described_class.at_mark_pct([ 80.0 ], 15.0)).to eq(80)
    end

    it "interpolates correctly at ratio = total_pct / 100" do
      # 5-point series spanning 0..1, total_pct = 50 → ratio = 0.5 → index 2
      series = [ 100.0, 75.0, 50.0, 25.0, 0.0 ]
      expect(described_class.at_mark_pct(series, 50.0)).to eq(50)
    end

    it "interpolates between two points for a non-integer position" do
      # 3-point series, total_pct = 25 → ratio = 0.25 → src_f = 0.5 → midpoint of idx 0,1
      series = [ 100.0, 60.0, 20.0 ]
      result = described_class.at_mark_pct(series, 25.0)
      # src_f = 0.25 × 2 = 0.5 → lo=0, hi=1, frac=0.5 → 100×0.5 + 60×0.5 = 80
      expect(result).to eq(80)
    end

    it "clamps ratio to 0..1" do
      series = [ 100.0, 50.0, 0.0 ]
      expect(described_class.at_mark_pct(series, 0.0)).to eq(100)
      expect(described_class.at_mark_pct(series, 100.0)).to eq(0)
    end
  end

  # ── .for (integration) ───────────────────────────────────────────────────────

  describe ".for" do
    context "with a single video with cached retention data" do
      let(:vid)            { create(:video, channel:) }
      let(:curve_data)     { retention_curve(length: 11) }
      let(:expected_curve) { curve_data.map { |r| r[:audience_watch_ratio] } }

      before do
        # Pre-populate the AnalyticsPrimitive cache for the video
        AnalyticsPrimitive.create!(
          video_youtube_id: vid.youtube_video_id,
          report:           "retention",
          start_date:       described_class::LIFETIME_START,
          end_date:         Date.new(2026, 6, 28),
          period_token:     "lifetime",
          metrics:          curve_data.map { |r| r.transform_keys(&:to_s) },
          fetched_at:       Time.current,
          expires_at:       1.hour.from_now
        )
        # Stub scalars for views weighting
        allow(Pito::Analytics::Primitives).to receive(:fetch)
          .with(hash_including(report: "scalars"))
          .and_return(vid.youtube_video_id => { "views" => 100 })
      end

      it "returns the cached retention curve as percentages" do
        groups = [ [ channel, [ vid.youtube_video_id ] ] ]
        result = described_class.for(groups:, window:, reference_date: Date.new(2026, 6, 28))
        expect(result.series.size).to eq(expected_curve.size)
        expect(result.series.first).to be_within(0.01).of(expected_curve.first * 100)
        expect(result.series.last).to  be_within(0.01).of(expected_curve.last  * 100)
      end

      it "computes total_pct as the mean of all ratio-bucket percentages" do
        groups = [ [ channel, [ vid.youtube_video_id ] ] ]
        result = described_class.for(groups:, window:, reference_date: Date.new(2026, 6, 28))
        expected_mean = (expected_curve.sum / expected_curve.size.to_f) * 100
        expect(result.total_pct).to be_within(0.1).of(expected_mean)
      end

      it "returns rel_performance as the views-weighted benchmark" do
        groups = [ [ channel, [ vid.youtube_video_id ] ] ]
        result = described_class.for(groups:, window:, reference_date: Date.new(2026, 6, 28))
        # All rows have relative_retention_performance: 1.0 → benchmark = 1.0 → "above average"
        expect(result.rel_performance).to be_within(0.01).of(1.0)
      end
    end

    context "with no usable data" do
      it "returns an empty result when groups is empty" do
        result = described_class.for(groups: [], window:)
        expect(result.series).to eq([])
        expect(result.total_pct).to eq(0.0)
        expect(result.rel_performance).to be_nil
      end

      it "returns an empty result when no retention curves are available" do
        vid = create(:video, channel:)
        groups = [ [ channel, [ vid.youtube_video_id ] ] ]

        # Scalars stub: views available
        allow(Pito::Analytics::Primitives).to receive(:fetch)
          .with(hash_including(report: "scalars"))
          .and_return(vid.youtube_video_id => { "views" => 100 })

        # Retention API stub: YouTube returns empty data
        allow_any_instance_of(Channel::Youtube::AnalyticsClient)
          .to receive(:retention).and_return([])

        result = described_class.for(groups:, window:, reference_date: Date.new(2026, 6, 28))
        expect(result.series).to eq([])
        expect(result.total_pct).to eq(0.0)
        expect(result.rel_performance).to be_nil
      end
    end

    context "with multiple videos (views-weighted average)" do
      let(:vid_a) { create(:video, channel:) }
      let(:vid_b) { create(:video, channel:) }

      # Two distinct 5-point curves (simplified for math)
      let(:curve_a) { 5.times.map { |i| { "audience_watch_ratio" => 1.0 - (i * 0.2) } } }
      let(:curve_b) { 5.times.map { |i| { "audience_watch_ratio" => 0.5 - (i * 0.1) } } }

      before do
        [ [ vid_a, curve_a ], [ vid_b, curve_b ] ].each do |vid, curve|
          AnalyticsPrimitive.create!(
            video_youtube_id: vid.youtube_video_id,
            report:           "retention",
            start_date:       described_class::LIFETIME_START,
            end_date:         Date.new(2026, 6, 28),
            period_token:     "lifetime",
            metrics:          curve,
            fetched_at:       Time.current,
            expires_at:       1.hour.from_now
          )
        end
        # vid_a gets 3× more views than vid_b
        allow(Pito::Analytics::Primitives).to receive(:fetch)
          .with(hash_including(report: "scalars"))
          .and_return(
            vid_a.youtube_video_id => { "views" => 300 },
            vid_b.youtube_video_id => { "views" => 100 }
          )
      end

      it "computes a views-weighted average across both curves" do
        groups = [ [ channel, [ vid_a.youtube_video_id, vid_b.youtube_video_id ] ] ]
        result = described_class.for(groups:, window:, reference_date: Date.new(2026, 6, 28))

        expect(result.series.size).to eq(5)
        # First bucket: 0.75×1.0 + 0.25×0.5 = 0.875 → 87.5%
        expect(result.series.first).to be_within(0.1).of(87.5)
      end
    end

    context "with a channel-level scope" do
      it "expands to the channel's videos and averages them" do
        vid = create(:video, channel:)
        curve = 5.times.map { |i| { "audience_watch_ratio" => 1.0 - (i * 0.2) } }

        AnalyticsPrimitive.create!(
          video_youtube_id: vid.youtube_video_id,
          report:           "retention",
          start_date:       described_class::LIFETIME_START,
          end_date:         Date.new(2026, 6, 28),
          period_token:     "lifetime",
          metrics:          curve,
          fetched_at:       Time.current,
          expires_at:       1.hour.from_now
        )
        allow(Pito::Analytics::Primitives).to receive(:fetch)
          .with(hash_including(report: "scalars"))
          .and_return(vid.youtube_video_id => { "views" => 100 })

        # Pass :channel subject (channel-level group)
        groups = [ [ channel, :channel ] ]
        result = described_class.for(groups:, window:, reference_date: Date.new(2026, 6, 28))
        expect(result.series.size).to eq(5)
        # First bucket: 1.0 × 100 = 100%
        expect(result.series.first).to be_within(0.01).of(100.0)
      end
    end
  end
end
