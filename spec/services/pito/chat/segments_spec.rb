# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Segments do
  let(:show_channel) { described_class.for(verb: :show, entity: :channel) }
  let(:show_vid)     { described_class.for(verb: :show, entity: :vid) }
  let(:show_game)    { described_class.for(verb: :show, entity: :game) }

  # ── .names ───────────────────────────────────────────────────────────────────

  describe ".names" do
    it "returns ordered names for show channel: detail, games, videos, at-a-glance" do
      expect(described_class.names(verb: :show, entity: :channel))
        .to eq(%w[detail games videos at-a-glance])
    end

    it "returns ordered names for show vid: detail, game, at-a-glance" do
      expect(described_class.names(verb: :show, entity: :vid))
        .to eq(%w[detail game at-a-glance])
    end

    it "returns ordered names for show game: detail, similar, videos, channels, at-a-glance" do
      expect(described_class.names(verb: :show, entity: :game))
        .to eq(%w[detail similar videos channels at-a-glance])
    end
  end

  # ── .default_names ───────────────────────────────────────────────────────────

  describe ".default_names" do
    it "returns [detail] for show channel" do
      expect(described_class.default_names(verb: :show, entity: :channel)).to eq(%w[detail])
    end

    it "returns [detail] for show vid" do
      expect(described_class.default_names(verb: :show, entity: :vid)).to eq(%w[detail])
    end

    it "returns [detail] for show game" do
      expect(described_class.default_names(verb: :show, entity: :game)).to eq(%w[detail])
    end
  end

  # ── kind invariant ───────────────────────────────────────────────────────────

  describe "segment kind" do
    context "show channel" do
      it "detail segment has kind :system" do
        expect(show_channel.find { |s| s.name == "detail" }.kind).to eq(:system)
      end

      it "non-detail segments all have kind :enhanced" do
        kinds = show_channel.reject { |s| s.name == "detail" }.map(&:kind).uniq
        expect(kinds).to eq([ :enhanced ])
      end
    end

    context "show vid" do
      it "detail segment has kind :system" do
        expect(show_vid.find { |s| s.name == "detail" }.kind).to eq(:system)
      end

      it "non-detail segments all have kind :enhanced" do
        kinds = show_vid.reject { |s| s.name == "detail" }.map(&:kind).uniq
        expect(kinds).to eq([ :enhanced ])
      end
    end

    context "show game" do
      it "detail segment has kind :system" do
        expect(show_game.find { |s| s.name == "detail" }.kind).to eq(:system)
      end

      it "non-detail segments all have kind :enhanced" do
        kinds = show_game.reject { |s| s.name == "detail" }.map(&:kind).uniq
        expect(kinds).to eq([ :enhanced ])
      end
    end
  end

  # ── builder / fill constants ─────────────────────────────────────────────────

  describe "builder constants" do
    it "every builder is a Module" do
      all_segs = show_channel + show_vid + show_game
      expect(all_segs.map(&:builder)).to all(be_a(Module))
    end
  end

  describe "fill constants" do
    it "non-nil fill values are Classes" do
      all_segs = show_channel + show_vid + show_game
      fills = all_segs.map(&:fill).compact
      expect(fills).to all(be_a(Class))
    end

    it "AnalyticsFillJob appears as a fill constant" do
      all_segs = show_channel + show_vid + show_game
      expect(all_segs.map(&:fill)).to include(AnalyticsFillJob)
    end

    it "ChannelDistributionFillJob is the fill for the game channels segment" do
      seg = show_game.find { |s| s.name == "channels" }
      expect(seg.fill).to eq(ChannelDistributionFillJob)
    end

    it "detail segments have nil fill" do
      detail_segs = [ show_channel, show_vid, show_game ].map { |segs| segs.find { |s| s.name == "detail" } }
      expect(detail_segs.map(&:fill)).to all(be_nil)
    end
  end

  # ── frozen table ─────────────────────────────────────────────────────────────

  describe "frozen table" do
    it ".for returns a frozen array" do
      expect(described_class.for(verb: :show, entity: :game)).to be_frozen
    end

    it "mutating the returned array raises FrozenError" do
      segments = described_class.for(verb: :show, entity: :game)
      expect { segments << :extra }.to raise_error(FrozenError)
    end
  end

  # ── ArgumentError on unknown verb / entity ───────────────────────────────────

  describe ".for error handling" do
    it "raises ArgumentError for an unknown verb" do
      expect { described_class.for(verb: :bogus, entity: :game) }
        .to raise_error(ArgumentError, /unknown verb/)
    end

    it "raises ArgumentError for an unknown entity on a known verb" do
      expect { described_class.for(verb: :show, entity: :playlist) }
        .to raise_error(ArgumentError, /unknown entity/)
    end

    it "raises ArgumentError for an unknown entity on :analyze" do
      expect { described_class.for(verb: :analyze, entity: :playlist) }
        .to raise_error(ArgumentError, /unknown entity/)
    end
  end

  # ── analyze verb ─────────────────────────────────────────────────────────────

  describe "analyze verb" do
    let(:analyze_channel) { described_class.for(verb: :analyze, entity: :channel) }
    let(:analyze_vid)     { described_class.for(verb: :analyze, entity: :vid) }
    let(:analyze_game)    { described_class.for(verb: :analyze, entity: :game) }

    describe ".names" do
      it "returns [numbers, breakdowns] for analyze channel" do
        expect(described_class.names(verb: :analyze, entity: :channel)).to eq(%w[numbers breakdowns])
      end

      it "returns [numbers, breakdowns] for analyze vid" do
        expect(described_class.names(verb: :analyze, entity: :vid)).to eq(%w[numbers breakdowns])
      end

      it "returns [numbers, breakdowns] for analyze game" do
        expect(described_class.names(verb: :analyze, entity: :game)).to eq(%w[numbers breakdowns])
      end
    end

    describe ".default_names" do
      it "returns [numbers] (the system segment) for all three entities" do
        %i[channel vid game].each do |entity|
          expect(described_class.default_names(verb: :analyze, entity:)).to eq(%w[numbers])
        end
      end
    end

    describe "segment kinds" do
      it "numbers has kind :system" do
        seg = analyze_vid.find { |s| s.name == "numbers" }
        expect(seg.kind).to eq(:system)
      end

      it "breakdowns has kind :enhanced" do
        seg = analyze_vid.find { |s| s.name == "breakdowns" }
        expect(seg.kind).to eq(:enhanced)
      end
    end

    describe "builder" do
      it "all analyze segments use Pito::MessageBuilder::Analyze::Message" do
        (analyze_channel + analyze_vid + analyze_game).each do |seg|
          expect(seg.builder).to eq(Pito::MessageBuilder::Analyze::Message)
        end
      end
    end

    describe "fill" do
      it "all analyze segments have nil fill (pipeline owns fan-out)" do
        (analyze_channel + analyze_vid + analyze_game).each do |seg|
          expect(seg.fill).to be_nil
        end
      end
    end

    describe "reply_target" do
      it "all analyze segments use :analyze_message" do
        (analyze_channel + analyze_vid + analyze_game).each do |seg|
          expect(seg.reply_target).to eq(:analyze_message)
        end
      end
    end

    describe "emit_if" do
      it "all analyze segments have nil emit_if (unconditional)" do
        (analyze_channel + analyze_vid + analyze_game).each do |seg|
          expect(seg.emit_if).to be_nil
        end
      end
    end

    describe "shared definition" do
      it "channel/vid/game analyze segments are equal (all share the same schema definition)" do
        expect(analyze_channel).to eq(analyze_vid)
        expect(analyze_vid).to eq(analyze_game)
      end
    end
  end

  # ── segment aliases (config-driven) ──────────────────────────────────────────

  describe "segment aliases" do
    it "the show/game 'similar' segment declares aliases: [\"similars\"]" do
      seg = show_game.find { |s| s.name == "similar" }
      expect(seg.aliases).to eq(%w[similars])
    end

    it "segments with no declared aliases have aliases: []" do
      seg = show_game.find { |s| s.name == "detail" }
      expect(seg.aliases).to eq([])
    end

    describe ".alias_map" do
      it "maps 'similars' → 'similar' for show/game" do
        map = described_class.alias_map(verb: :show, entity: :game)
        expect(map["similars"]).to eq("similar")
      end

      it "maps canonical names to themselves (identity)" do
        map = described_class.alias_map(verb: :show, entity: :game)
        expect(map["similar"]).to eq("similar")
        expect(map["detail"]).to eq("detail")
      end

      it "has exactly the canonical names (plus aliases) as keys for show/game" do
        map = described_class.alias_map(verb: :show, entity: :game)
        canonical_names = %w[detail similar videos channels at-a-glance]
        expect(map.keys).to match_array(canonical_names + %w[similars vids linked-vids])
      end

      it "has canonical names plus the videos alias (vids) as keys for show/channel" do
        map = described_class.alias_map(verb: :show, entity: :channel)
        expect(map.keys).to match_array(%w[detail games videos at-a-glance] + %w[vids])
      end
    end
  end

  # ── DISJOINTNESS GUARD (config-rot tripwire) ──────────────────────────────────
  # If a metric token is ever renamed to collide with an analyze segment name,
  # this example fails — preventing the SegmentSelection extra_vocabulary
  # pass-through from silently swallowing a segment token.

  describe "analyze segment ↔ metric token disjointness" do
    it "analyze segment names do not collide with any MetricSelection token (canonical keys + aliases)" do
      segment_names = described_class.names(verb: :analyze, entity: :vid).to_set
      metric_tokens = (Pito::Analytics::MetricSelection::ALIASES.keys +
                       Pito::Analytics::MetricOrder::METRICS.keys.map(&:to_s)).to_set
      expect(segment_names & metric_tokens).to be_empty,
        "Collision detected: #{(segment_names & metric_tokens).to_a.inspect} — " \
        "rename the segment or the metric token before proceeding."
    end
  end

  # ── emit_if lambdas ──────────────────────────────────────────────────────────

  describe "emit_if lambdas" do
    context "show channel: videos segment (guards on channel.videos.any?)" do
      let(:segment) { show_channel.find { |s| s.name == "videos" } }

      it "returns false when the channel has no videos" do
        channel = double("channel", videos: double("videos", any?: false))
        expect(segment.emit_if.call(channel)).to be(false)
      end

      it "returns true when the channel has videos" do
        channel = double("channel", videos: double("videos", any?: true))
        expect(segment.emit_if.call(channel)).to be(true)
      end
    end

    context "show vid: game segment (guards on vid.linked_games.first.present?)" do
      let(:segment) { show_vid.find { |s| s.name == "game" } }

      it "returns falsy when linked_games.first is nil" do
        vid = double("vid", linked_games: double("games", first: nil))
        expect(segment.emit_if.call(vid)).to be_falsy
      end

      it "returns truthy when linked_games.first is present" do
        vid = double("vid", linked_games: double("games", first: "a-game"))
        expect(segment.emit_if.call(vid)).to be_truthy
      end
    end

    context "show game: videos segment (guards on game.linked_videos.any?)" do
      let(:segment) { show_game.find { |s| s.name == "videos" } }

      it "returns false when the game has no linked videos" do
        game = double("game", linked_videos: double("videos", any?: false))
        expect(segment.emit_if.call(game)).to be(false)
      end

      it "returns true when the game has linked videos" do
        game = double("game", linked_videos: double("videos", any?: true))
        expect(segment.emit_if.call(game)).to be(true)
      end
    end

    context "unconditional segments have nil emit_if" do
      it "all detail segments have nil emit_if" do
        detail_segs = [ show_channel, show_vid, show_game ].map { |segs| segs.find { |s| s.name == "detail" } }
        expect(detail_segs.map(&:emit_if)).to all(be_nil)
      end

      it "all at-a-glance segments have nil emit_if" do
        glance_segs = [ show_channel, show_vid, show_game ].map { |segs| segs.find { |s| s.name == "at-a-glance" } }
        expect(glance_segs.map(&:emit_if)).to all(be_nil)
      end

      it "show game similar segment has nil emit_if" do
        seg = show_game.find { |s| s.name == "similar" }
        expect(seg.emit_if).to be_nil
      end

      it "show game channels segment has nil emit_if" do
        seg = show_game.find { |s| s.name == "channels" }
        expect(seg.emit_if).to be_nil
      end
    end
  end
end
