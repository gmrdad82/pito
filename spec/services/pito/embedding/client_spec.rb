# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Embedding::Client, type: :service do
  let(:base_url) { "http://127.0.0.1:8091" }
  let(:embeddings_endpoint) { "#{base_url}/v1/embeddings" }

  def set_embedder_url(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PITO_EMBEDDER_URL").and_return(value)
  end

  describe "#embed" do
    context "when the response data arrives out of order" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(
          status:  200,
          body:    {
            data: [
              { index: 1, embedding: [ 0.2 ] },
              { index: 0, embedding: [ 0.1 ] }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "returns embeddings in input order (index field wins)" do
        result = described_class.new.embed([ "first", "second" ])
        expect(result).to eq([ [ 0.1 ], [ 0.2 ] ])
      end
    end

    context "when the URL is unconfigured" do
      before { set_embedder_url(nil) }

      it "returns an all-nil array and makes no HTTP request" do
        stub = stub_request(:post, %r{.*})
        result = described_class.new.embed([ "hello", "world" ])
        expect(result).to eq([ nil, nil ])
        expect(stub).not_to have_been_requested
      end
    end

    context "when all inputs are blank" do
      before { set_embedder_url(base_url) }

      it "returns nils without an HTTP call" do
        stub = stub_request(:post, embeddings_endpoint)
        result = described_class.new.embed([ "", "   " ])
        expect(result).to eq([ nil, nil ])
        expect(stub).not_to have_been_requested
      end
    end

    context "on a 500 response" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(status: 500, body: "boom")
      end

      it "returns nils without raising" do
        result = described_class.new.embed([ "hello" ])
        expect(result).to eq([ nil ])
      end
    end

    context "on a network error" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_timeout
      end

      it "returns nils without raising" do
        result = described_class.new.embed([ "hello" ])
        expect(result).to eq([ nil ])
      end
    end
  end

  describe "#embed_batch" do
    context "happy path" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(
          status:  200,
          body:    {
            data: [
              { index: 0, embedding: [ 0.1 ] },
              { index: 1, embedding: [ 0.2 ] }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "returns ordered embeddings" do
        result = described_class.new.embed_batch(inputs: [ "a", "b" ])
        expect(result).to eq([ [ 0.1 ], [ 0.2 ] ])
      end
    end

    context "on a non-2xx response" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(status: 503, body: "unavailable")
      end

      it "raises Error naming the response code" do
        expect { described_class.new.embed_batch(inputs: [ "a" ]) }
          .to raise_error(Pito::Embedding::Client::Error, /503/)
      end
    end

    context "on a network error" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_timeout
      end

      it "reports the original exception to AppSignal before raising the wrapped Error" do
        expect(Appsignal).to receive(:report_error) do |error|
          expect(error).not_to be_a(Pito::Embedding::Client::Error)
        end

        expect { described_class.new.embed_batch(inputs: [ "a" ]) }
          .to raise_error(Pito::Embedding::Client::Error, /embedder request failed/)
      end
    end

    context "when the URL is unconfigured" do
      before { set_embedder_url(nil) }

      it "raises Error mentioning PITO_EMBEDDER_URL" do
        expect { described_class.new.embed_batch(inputs: [ "a" ]) }
          .to raise_error(Pito::Embedding::Client::Error, /PITO_EMBEDDER_URL/)
      end
    end

    context "above MAX_BATCH_SIZE" do
      before { set_embedder_url(base_url) }

      it "raises ArgumentError without making an HTTP call" do
        stub = stub_request(:post, embeddings_endpoint)
        inputs = Array.new(129) { |i| "input-#{i}" }

        expect { described_class.new.embed_batch(inputs: inputs) }.to raise_error(ArgumentError)
        expect(stub).not_to have_been_requested
      end
    end

    context "when a response slot is missing" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(
          status:  200,
          body:    { data: [ { index: 0, embedding: [ 0.1 ] } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "raises Error naming the missing indices" do
        expect { described_class.new.embed_batch(inputs: [ "a", "b" ]) }
          .to raise_error(Pito::Embedding::Client::Error, /missing/)
      end
    end
  end

  describe "DIMENSIONS" do
    it "is locked at 768 (matches the pgvector columns)" do
      expect(described_class::DIMENSIONS).to eq(768)
    end
  end
end
