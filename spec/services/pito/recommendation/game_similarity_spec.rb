# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::GameSimilarity, type: :service do
  # 1024-dim unit vector with one hot dimension → predictable cosine distance:
  # identical hot dim ⇒ distance 0 (E=100); orthogonal hot dims ⇒ distance 1 (E=0).
  def vec(index, value: 1.0)
    Array.new(1024, 0.0).tap { |a| a[index] = value }
  end

  def make_game(embedding: nil, genres: [], developers: [], publishers: [], score: nil)
    g = create(:game)
    g.update_column(:summary_embedding, embedding) unless embedding.nil?
    g.update_column(:score, score) unless score.nil?
    genres.each     { |ge| create(:game_genre,     game: g, genre: ge) }
    developers.each { |c|  create(:game_developer, game: g, company: c) }
    publishers.each { |c|  create(:game_publisher, game: g, company: c) }
    g.reload
  end

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
    target = make_game(embedding: vec(0), genres: [ genre_x ], developers: [ dev_a ], publishers: [ pub_b ], score: 80)
    make_game(embedding: vec(0), genres: [ genre_x ], developers: [ dev_a ], publishers: [ pub_b ], score: 80)

    result = described_class.call(target).first
    expect(result.score).to eq(100)
    expect(result.breakdown).to eq(e: 100.0, g: 100.0, d: 100.0, p: 100.0, s: 100.0)
  end

  it "scores an embedding-only identical match at 45 (E weight)" do
    target = make_game(embedding: vec(0))
    make_game(embedding: vec(0))
    expect(described_class.call(target).first.score).to eq(45)
  end

  it "adds genre overlap on top of embedding (45 → 65)" do
    target  = make_game(embedding: vec(0), genres: [ genre_x ])
    with_g  = make_game(embedding: vec(0), genres: [ genre_x ])
    without = make_game(embedding: vec(0))

    by_game = described_class.call(target).index_by(&:game)
    expect(by_game[with_g].score).to eq(65)
    expect(by_game[without].score).to eq(45)
  end

  it "weights a shared developer above a shared publisher (57 vs 53)" do
    target = make_game(embedding: vec(0), developers: [ dev_a ], publishers: [ pub_b ])
    dev    = make_game(embedding: vec(0), developers: [ dev_a ])
    pub    = make_game(embedding: vec(0), publishers: [ pub_b ])

    by_game = described_class.call(target).index_by(&:game)
    expect(by_game[dev].score).to eq(57)
    expect(by_game[pub].score).to eq(53)
    expect(by_game[dev].score).to be > by_game[pub].score
  end

  it "ranks a closer score higher than a distant one" do
    target = make_game(embedding: vec(0), score: 80)
    close  = make_game(embedding: vec(0), score: 80)
    far    = make_game(embedding: vec(0), score: 20)

    by_game = described_class.call(target).index_by(&:game)
    expect(by_game[close].score).to be > by_game[far].score
  end

  # ── floor + facets ─────────────────────────────────────────────────────────

  it "drops a candidate below the 25 floor (orthogonal embedding, single genre = 20)" do
    target = make_game(embedding: vec(0), genres: [ genre_x ])
    weak   = make_game(embedding: vec(1), genres: [ genre_x ]) # E=0, G=100 → blend 20

    expect(described_class.call(target).map(&:game)).not_to include(weak)
  end

  it "surfaces a facet-similar game even when the target has no embedding" do
    target = make_game(embedding: nil, genres: [ genre_x ], developers: [ dev_a ])
    # shares genre + developer → G=100, D=100 → blend 32 (above floor), no embedding
    cand = make_game(embedding: nil, genres: [ genre_x ], developers: [ dev_a ])

    result = described_class.call(target).find { |r| r.game == cand }
    expect(result).to be_present
    expect(result.score).to eq(32)
    expect(result.breakdown[:e]).to eq(0.0)
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
    target = make_game(embedding: vec(0))
    3.times { make_game(embedding: vec(0)) }
    expect(described_class.call(target, limit: 2).size).to eq(2)
  end
end
