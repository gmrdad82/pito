# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Search::Semantic, type: :service do
  let(:client) { instance_double(Pito::Embedding::Client) }

  # A `size`-long zero vector with the given dimension => value pairs set.
  # Magnitude is irrelevant — pgvector's cosine `<=>` operator is scale-
  # invariant — so choosing (x, y) with x**2 + y**2 == 1 makes the cosine
  # similarity against the e0 query vector below equal EXACTLY x, giving
  # every example a deterministic, hand-computable similarity.
  def vec(size, values)
    Array.new(size, 0.0).tap { |a| values.each { |i, v| a[i] = v } }
  end

  def stub_embed(vector)
    allow(Pito::Embedding::Client).to receive(:new).and_return(client)
    allow(client).to receive(:embed).and_return([ vector ])
  end

  it "defaults the floor to 0.55 (see DEFAULT_FLOOR's comment for the measured gap)" do
    expect(described_class::DEFAULT_FLOOR).to eq(0.55)
  end

  # Runs the full behavioral contract against a real `has_neighbors`-enabled
  # model + its `summary_embedding` column — proving the class carries no
  # domain knowledge by running it, unmodified, against both Game and Video.
  shared_examples "a pgvector semantic search" do |model_class:, factory:|
    let(:column)       { model_class::EMBEDDING_COLUMN }
    let(:size)          { model_class.columns_hash[column.to_s].limit }
    let(:query_vector)  { vec(size, 0 => 1.0) }

    it "drops a row whose similarity is below the floor" do
      stub_embed(query_vector)
      loser = create(factory)
      loser.update_column(column, vec(size, 0 => 0.5, 1 => Math.sqrt(0.75))) # similarity 0.50

      result = described_class.call(scope: model_class.all, column: column, query: "anything", limit: 10)
      expect(result).to eq([])
    end

    it "keeps rows at/above the floor, ordered by similarity desc" do
      stub_embed(query_vector)
      mid = create(factory)
      mid.update_column(column, vec(size, 0 => 0.6, 1 => 0.8)) # similarity 0.60
      highest = create(factory)
      highest.update_column(column, vec(size, 0 => 1.0)) # similarity 1.0 (exact match)

      result = described_class.call(scope: model_class.all, column: column, query: "anything", limit: 10)

      expect(result.map { |r| r[:record] }).to eq([ highest, mid ])
      similarities = result.map { |r| r[:similarity] }
      expect(similarities).to eq(similarities.sort.reverse)
      expect(result.first[:similarity]).to be_within(0.0001).of(1.0)
      expect(result.last[:similarity]).to be_within(0.0001).of(0.6)
    end

    it "keeps a row whose measured similarity exactly equals the floor (inclusive boundary)" do
      stub_embed(query_vector)
      record = create(factory)
      record.update_column(column, vec(size, 0 => 0.6, 1 => 0.8))

      # Measure the real similarity Postgres/Ruby computed for this pair
      # (floor: 0.0 so nothing is filtered), then re-run with floor set to
      # that EXACT value — proves the comparison is `>=`, not `>`, without
      # trusting a hand-computed value to match pgvector's arithmetic bit
      # for bit.
      baseline = described_class.call(scope: model_class.all, column: column, query: "q", limit: 5, floor: 0.0)
      measured = baseline.first[:similarity]

      result = described_class.call(scope: model_class.all, column: column, query: "q", limit: 5, floor: measured)
      expect(result.map { |r| r[:record] }).to eq([ record ])
    end

    it "honors limit" do
      stub_embed(query_vector)
      Array.new(3) { create(factory) }.each { |r| r.update_column(column, vec(size, 0 => 1.0)) }

      result = described_class.call(scope: model_class.all, column: column, query: "q", limit: 2)
      expect(result.length).to eq(2)
    end

    it "returns nil when the embedder is unavailable (client returned a nil vector)" do
      allow(Pito::Embedding::Client).to receive(:new).and_return(client)
      allow(client).to receive(:embed).and_return([ nil ])
      record = create(factory)
      record.update_column(column, vec(size, 0 => 1.0))

      result = described_class.call(scope: model_class.all, column: column, query: "q", limit: 5)
      expect(result).to be_nil
    end

    it "returns [] when nothing clears the floor" do
      stub_embed(query_vector)
      record = create(factory)
      record.update_column(column, vec(size, 1 => 1.0)) # orthogonal to the query — similarity 0.0

      result = described_class.call(scope: model_class.all, column: column, query: "q", limit: 5)
      expect(result).to eq([])
    end

    it "excludes rows with no stored embedding" do
      stub_embed(query_vector)
      create(factory) # no embedding written

      result = described_class.call(scope: model_class.all, column: column, query: "q", limit: 5)
      expect(result).to eq([])
    end

    it "embeds the raw query text via Client#embed (the client applies the wire prefix itself)" do
      stub_embed(query_vector)
      record = create(factory)
      record.update_column(column, vec(size, 0 => 1.0))

      described_class.call(scope: model_class.all, column: column, query: "a raw query", limit: 5)

      expect(client).to have_received(:embed).with([ "a raw query" ])
    end
  end

  describe "against Game.summary_embedding" do
    it_behaves_like "a pgvector semantic search", model_class: Game, factory: :game
  end

  describe "against Video.summary_embedding" do
    it_behaves_like "a pgvector semantic search", model_class: Video, factory: :video
  end
end
