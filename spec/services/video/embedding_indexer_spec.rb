# frozen_string_literal: true

require "rails_helper"

RSpec.describe Video::EmbeddingIndexer, type: :service do
  let(:video) do
    create(:video, title: "Lies of P — Boss Guide", description: "Every boss.", tags: %w[soulslike], category_id: "20")
  end
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
    expect { described_class.call(video) }.to change { video.reload.embedded_digest }.from(nil)
    expect(video.embedding_vector).to be_present
  end

  it "no-ops when the indexed text is unchanged" do
    described_class.call(video)
    expect(client).not_to receive(:embed_batch)
    described_class.call(video.reload)
  end

  it "re-embeds when an indexed field changes" do
    described_class.call(video)
    video.update_column(:description, "A different focus.")
    expect(client).to receive(:embed_batch).and_return([ Array.new(768, 0.2) ])
    described_class.call(video.reload)
  end

  it "force: re-embeds even when the digest is unchanged" do
    described_class.call(video)
    expect(client).to receive(:embed_batch).and_return([ Array.new(768, 0.3) ])
    described_class.call(video.reload, force: true)
  end

  it "no-ops without an HTTP call when PITO_EMBEDDER_URL is blank" do
    set_embedder_url(nil)
    expect(Pito::Embedding::Client).not_to receive(:new)
    expect { described_class.call(video) }.not_to change { video.reload.embedded_digest }
    expect(video.embedding_vector).not_to be_present
  end

  it "raises Pito::Error::EmbeddingNil when embed_batch returns [ nil ]" do
    allow(client).to receive(:embed_batch).and_return([ nil ])
    expect { described_class.call(video) }.to raise_error(Pito::Error::EmbeddingNil)
  end

  it "carries the client failure as the cause in the raised message" do
    allow(client).to receive(:embed_batch)
      .and_raise(Pito::Embedding::Client::Error, "Embedder non-2xx response: 429 Too Many Requests")
    expect { described_class.call(video) }.to raise_error(
      Pito::Error::EmbeddingNil, /video ##{video.id}.*429 Too Many Requests/
    )
  end
end
