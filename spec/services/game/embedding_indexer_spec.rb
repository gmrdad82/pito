# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::EmbeddingIndexer, type: :service do
  let(:game) { create(:game, title: "Lies of P", summary: "A soulslike.") }
  let(:client) { instance_double(Pito::Embedding::Client) }
  let(:embedder_url) { "http://127.0.0.1:8091" }

  def set_embedder_url(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PITO_EMBEDDER_URL").and_return(value)
  end

  before do
    set_embedder_url(embedder_url)
    allow(Pito::Embedding::Client).to receive(:new).and_return(client)
    allow(client).to receive(:embed_batch).and_return([ Array.new(768, 0.1) ])
  end

  it "embeds and stores the digest on first index" do
    expect { described_class.call(game) }.to change { game.reload.embedded_digest }.from(nil)
    expect(game.embedding_vector).to be_present
  end

  it "salts the stored digest with Pito::Embedding::Client::VECTOR_SPACE (3.0.1 vector-space fix)" do
    described_class.call(game)

    expected = Digest::SHA256.hexdigest(Pito::Embedding::Client::VECTOR_SPACE + Game::EmbedText.call(game.reload))
    expect(game.reload.embedded_digest).to eq(expected)
    expect(game.embedded_digest).not_to eq(Digest::SHA256.hexdigest(Game::EmbedText.call(game)))
  end

  it "re-embeds when the stored digest was computed under a different VECTOR_SPACE, even though the text and vector are otherwise unchanged" do
    described_class.call(game)
    stale_digest = Digest::SHA256.hexdigest("some-other-vector-space" + Game::EmbedText.call(game.reload))
    game.update_column(:embedded_digest, stale_digest)
    expect(game.reload.embedding_vector).to be_present

    expect(client).to receive(:embed_batch).and_return([ Array.new(768, 0.5) ])
    described_class.call(game.reload)

    expect(game.reload.embedded_digest)
      .to eq(Digest::SHA256.hexdigest(Pito::Embedding::Client::VECTOR_SPACE + Game::EmbedText.call(game)))
  end

  it "no-ops when the indexed text is unchanged" do
    described_class.call(game)
    expect(client).not_to receive(:embed_batch)
    described_class.call(game.reload)
  end

  it "re-embeds when the digest matches but the vector is nil (2.x -> 3.0.0 upgrade state)" do
    described_class.call(game)
    game.reload.update_column(Game::EMBEDDING_COLUMN, nil)

    expect(client).to receive(:embed_batch).and_return([ Array.new(768, 0.4) ])
    expect { described_class.call(game.reload) }
      .to change { game.reload.embedding_vector }.from(nil)
  end

  it "still skips when the digest matches and a vector is already present" do
    described_class.call(game)
    expect(game.reload.embedding_vector).to be_present

    expect(client).not_to receive(:embed_batch)
    described_class.call(game.reload)
  end

  it "re-embeds when an indexed field changes" do
    described_class.call(game)
    game.update_column(:summary, "A different summary entirely.")
    expect(client).to receive(:embed_batch).and_return([ Array.new(768, 0.2) ])
    described_class.call(game.reload)
  end

  it "re-embeds when the game's traits change — the digest shift this produces is what lets the 02:00 nightly reindex (NightlyReindexJob) auto re-embed a newly classified game with no force flag" do
    described_class.call(game)
    game.update_column(:traits, {
      "schema_version" => 1,
      "values" => { "difficulty" => "brutal" },
      "sources" => { "difficulty" => "classified" }
    })
    expect(client).to receive(:embed_batch).and_return([ Array.new(768, 0.6) ])
    described_class.call(game.reload)
  end

  it "force: re-embeds even when the digest is unchanged" do
    described_class.call(game)
    expect(client).to receive(:embed_batch).and_return([ Array.new(768, 0.3) ])
    described_class.call(game.reload, force: true)
  end

  it "no-ops without an HTTP call when PITO_EMBEDDER_URL is blank" do
    set_embedder_url(nil)
    expect(Pito::Embedding::Client).not_to receive(:new)
    expect { described_class.call(game) }.not_to change { game.reload.embedded_digest }
    expect(game.embedding_vector).not_to be_present
  end

  it "raises Pito::Error::EmbeddingNil when embed_batch returns [ nil ]" do
    allow(client).to receive(:embed_batch).and_return([ nil ])
    expect { described_class.call(game) }.to raise_error(Pito::Error::EmbeddingNil)
  end

  it "carries the client failure as the cause in the raised message" do
    allow(client).to receive(:embed_batch)
      .and_raise(Pito::Embedding::Client::Error, "Embedder non-2xx response: 429 Too Many Requests")
    expect { described_class.call(game) }.to raise_error(
      Pito::Error::EmbeddingNil, /game ##{game.id}.*429 Too Many Requests/
    )
  end
end
