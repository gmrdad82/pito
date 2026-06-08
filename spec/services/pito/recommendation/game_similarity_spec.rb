# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::GameSimilarity, type: :service do
  # 1024-dim unit vector with one hot dimension → predictable cosine distance:
  # identical hot dim ⇒ distance 0 (E=100); orthogonal hot dims ⇒ distance 1 (E=0).
  def vec(index, value: 1.0)
    Array.new(1024, 0.0).tap { |a| a[index] = value }
  end

  def make_game(embedding: nil, genres: [], developers: [], publishers: [], score: nil,
                themes: [], perspectives: [])
    g = create(:game)
    g.update_column(:summary_embedding, embedding) unless embedding.nil?
    g.update_column(:score, score) unless score.nil?
    g.update_columns(themes: themes, player_perspectives: perspectives)
    genres.each     { |ge| create(:game_genre,     game: g, genre: ge) }
    developers.each { |c|  create(:game_developer, game: g, company: c) }
    publishers.each { |c|  create(:game_publisher, game: g, company: c) }
    g.reload
  end

  W = Pito::Recommendation::Weights

  let(:genre_x) { create(:genre) }
  let(:dev_a)   { create(:company) }
  let(:pub_b)   { create(:company) }

  # ── guards ───────────────────────────────────────────────────────────────

  it "returns [] for a nil game" do
    expect(described_class.call(nil)).to eq([])
  end

  it "returns [] when there are no candidate games" do
    target = make_game(embedding: vec(0))
    expect(described_class.call(target)).to eq([])
  end

  it "never includes the target game itself" do
    target = make_game(embedding: vec(0))
    make_game(embedding: vec(0))
    results = described_class.call(target)
    expect(results.map(&:game)).not_to include(target)
  end

  # ── single-signal weighting (embedding stays identical ⇒ E=100 is stable) ──

  it "scores an identical-everything twin at 100 with a full breakdown" do
    # score: 100 (elite) → score_smile(100,100) = 100 → all signals 100 → blend 100
    facets = { genres: [ genre_x ], developers: [ dev_a ], publishers: [ pub_b ],
               score: 100, themes: [ "Action" ], perspectives: [ "Third person" ] }
    target = make_game(embedding: vec(0), **facets)
    make_game(embedding: vec(0), **facets)

    result = described_class.call(target).first
    expect(result.score).to eq(100)
    # no ttb_main_seconds / release_year / platforms set by factory → those signals are absent
    expect(result.breakdown).to eq(e: 100.0, g: 100.0, t: 100.0, pp: 100.0, s: 100.0, d: 100.0, p: 100.0)
  end

  it "scores an embedding-only identical match by the E weight alone" do
    target = make_game(embedding: vec(0))
    make_game(embedding: vec(0))
    expect(described_class.call(target).first.score).to eq(W.blend(e: 100))
  end

  it "adds genre overlap on top of embedding" do
    target  = make_game(embedding: vec(0), genres: [ genre_x ])
    with_g  = make_game(embedding: vec(0), genres: [ genre_x ])
    # target HAS genre_x → genre facet is PRESENT for the pair (union non-empty)
    # → without gets g: 0.0 in its breakdown (not absent), dragging its score down
    without = make_game(embedding: vec(0))

    by_game = described_class.call(target).index_by(&:game)
    expect(by_game[with_g].score).to eq(W.blend(e: 100, g: 100))
    expect(by_game[without].score).to eq(W.blend(e: 100, g: 0))
  end

  it "weights a shared developer above a shared publisher" do
    target = make_game(embedding: vec(0), developers: [ dev_a ], publishers: [ pub_b ])
    dev    = make_game(embedding: vec(0), developers: [ dev_a ])
    pub    = make_game(embedding: vec(0), publishers: [ pub_b ])

    by_game = described_class.call(target).index_by(&:game)
    # target has pub_b → publisher facet is present for the dev candidate (p: 0)
    # target has dev_a → developer facet is present for the pub candidate (d: 0)
    expect(by_game[dev].score).to eq(W.blend(e: 100, d: 100, p: 0))
    expect(by_game[pub].score).to eq(W.blend(e: 100, p: 100, d: 0))
    expect(by_game[dev].score).to be > by_game[pub].score
  end

  it "weights a shared genre as the strongest single facet signal" do
    # G=0.22 > PP=0.20; orthogonal embedding (E=0) present on both candidates
    target    = make_game(embedding: vec(0), genres: [ genre_x ])
    with_genre = make_game(embedding: vec(1), genres: [ genre_x ]) # orthogonal embed, shares genre only
    none       = make_game(embedding: vec(1), perspectives: [ "Third person" ]) # orthogonal, no shared genre

    results = described_class.call(target).index_by(&:game)
    expect(results[with_genre].score).to eq(W.blend(e: 0, g: 100))
    expect(results[with_genre].score).to be > W.blend(e: 0, pp: 100)
    expect(results).not_to have_key(none) # only pp: 0 + e: 0 shared → below floor
  end

  it "ranks a closer score higher than a distant one" do
    target = make_game(embedding: vec(0), score: 80)
    close  = make_game(embedding: vec(0), score: 80)
    far    = make_game(embedding: vec(0), score: 20)

    by_game = described_class.call(target).index_by(&:game)
    expect(by_game[close].score).to be > by_game[far].score
  end

  # ── floor + facets ─────────────────────────────────────────────────────────

  it "drops a candidate below the floor (orthogonal embedding, nothing shared → 0)" do
    target = make_game(embedding: vec(0), genres: [ genre_x ])
    weak   = make_game(embedding: vec(1)) # E=0, no shared facets → blend 0 < floor

    expect(described_class.call(target).map(&:game)).not_to include(weak)
  end

  it "surfaces a facet-similar game even when the target has no embedding" do
    target = make_game(embedding: nil, genres: [ genre_x ], developers: [ dev_a ])
    # shares genre + developer → G=100, D=100, no embedding
    cand = make_game(embedding: nil, genres: [ genre_x ], developers: [ dev_a ])

    result = described_class.call(target).find { |r| r.game == cand }
    expect(result).to be_present
    expect(result.score).to eq(W.blend(g: 100, d: 100))
    expect(result.breakdown[:e]).to be_nil # no embedding on either → e absent from breakdown
  end

  # ── invariants ─────────────────────────────────────────────────────────────

  it "every result's breakdown blends back to its reported score" do
    target = make_game(embedding: vec(0), genres: [ genre_x ], developers: [ dev_a ], score: 70)
    make_game(embedding: vec(0), genres: [ genre_x ], score: 70)
    make_game(embedding: vec(0), developers: [ dev_a ])

    described_class.call(target).each do |r|
      expect(Pito::Recommendation::Weights.blend(r.breakdown)).to eq(r.score)
    end
  end

  it "returns results ranked best-first" do
    target = make_game(embedding: vec(0), genres: [ genre_x ])
    make_game(embedding: vec(0), genres: [ genre_x ]) # 65
    make_game(embedding: vec(0))                      # 45

    scores = described_class.call(target).map(&:score)
    expect(scores).to eq(scores.sort.reverse)
  end

  it "honours the limit: keyword" do
    # Pin the candidates to the target via a SHARED GENRE so they land in the
    # deterministic facet pool, not just the approximate embedding pool — this
    # keeps the test order-independent (it used to flake under suite ordering
    # when the HNSW pool crowded the vec(0) twins out).
    genre  = create(:genre, name: "Shared Pool Genre")
    target = make_game(embedding: vec(0), genres: [ genre ])
    3.times { make_game(embedding: vec(0), genres: [ genre ]) }
    expect(described_class.call(target, limit: 2).size).to eq(2)
  end

  # ── pairwise .between (the composition primitive, no pool / no floor) ───────

  describe ".between" do
    it "blends two specific games and is not floored (genre + developer)" do
      g1 = make_game(embedding: nil, genres: [ genre_x ], developers: [ dev_a ])
      g2 = make_game(embedding: nil, genres: [ genre_x ], developers: [ dev_a ])
      out = described_class.between(g1, g2)
      expect(out[:score]).to eq(W.blend(g: 100, d: 100))
      # no embedding / themes / perspectives / publishers / score on these games →
      # only the signals with a non-empty union are present in the breakdown
      expect(out[:breakdown]).to eq(g: 100.0, d: 100.0)
    end

    it "computes cosine embedding similarity in Ruby (identical = E 100)" do
      g1 = make_game(embedding: vec(0))
      g2 = make_game(embedding: vec(0))
      expect(described_class.between(g1, g2)[:breakdown][:e]).to eq(100.0)
    end

    it "is 0 when the two games share nothing and have no embedding" do
      g1 = make_game(embedding: nil)
      g2 = make_game(embedding: nil)
      expect(described_class.between(g1, g2)[:score]).to eq(0)
    end

    it "is symmetric" do
      g1 = make_game(embedding: vec(0), genres: [ genre_x ], score: 80)
      g2 = make_game(embedding: vec(1), score: 60)
      expect(described_class.between(g1, g2)[:score]).to eq(described_class.between(g2, g1)[:score])
    end
  end

  describe ".cosine_distance" do
    it "is 0 for identical vectors and ~1 for orthogonal" do
      expect(described_class.cosine_distance([ 1.0, 0.0 ], [ 1.0, 0.0 ])).to be_within(1e-9).of(0.0)
      expect(described_class.cosine_distance([ 1.0, 0.0 ], [ 0.0, 1.0 ])).to be_within(1e-9).of(1.0)
    end

    it "returns nil when a vector is missing or zero" do
      expect(described_class.cosine_distance(nil, [ 1.0 ])).to be_nil
      expect(described_class.cosine_distance([ 0.0, 0.0 ], [ 1.0, 0.0 ])).to be_nil
    end
  end
end
