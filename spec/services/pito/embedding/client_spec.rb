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

    context "when the input is within the chunk budget" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(
          status:  200,
          body:    { data: [ { index: 0, embedding: [ 3.0, 4.0 ] } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "makes a single request and returns the chunk vector unpooled" do
        result = described_class.new.embed([ "short input" ])
        expect(result).to eq([ [ 3.0, 4.0 ] ])
        expect(a_request(:post, embeddings_endpoint)).to have_been_made.once
      end
    end

    context "when the input exceeds the chunk budget" do
      let(:long_text) { (("lorem ipsum dolor sit amet consectetur adipiscing elit ") * 30).strip }

      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return do |request|
          inputs = JSON.parse(request.body)["input"]
          data = inputs.each_index.map { |i| { index: i, embedding: [ i + 1.0, i + 2.0 ] } }
          { status: 200, body: { data: data }.to_json, headers: { "Content-Type" => "application/json" } }
        end
      end

      it "chunks the input and returns the L2-normalized mean of the chunk vectors" do
        chunk_count = described_class.new.send(:chunk_text, long_text).length
        expect(chunk_count).to be > 1

        mean = [
          (0...chunk_count).sum { |i| i + 1.0 } / chunk_count,
          (0...chunk_count).sum { |i| i + 2.0 } / chunk_count
        ]
        norm = Math.sqrt(mean.sum { |v| v**2 })
        expected = mean.map { |v| v / norm }

        result = described_class.new.embed([ long_text ]).first
        expect(result.length).to eq(2)
        result.each_with_index { |v, i| expect(v).to be_within(0.0001).of(expected[i]) }
      end
    end

    context "when some chunks of a long input fail to embed" do
      let(:long_text) { (("lorem ipsum dolor sit amet consectetur adipiscing elit ") * 30).strip }

      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(
          status:  200,
          body:    { data: [ { index: 0, embedding: [ 0.4, 0.3 ] } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "pools whatever chunk vectors survived" do
        chunk_count = described_class.new.send(:chunk_text, long_text).length
        expect(chunk_count).to be > 1

        result = described_class.new.embed([ long_text ]).first
        expect(result).to eq([ 0.4, 0.3 ])
      end
    end

    context "when every chunk of a long input fails to embed" do
      let(:long_text) { (("lorem ipsum dolor sit amet consectetur adipiscing elit ") * 30).strip }

      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(status: 500, body: "boom")
      end

      it "returns a nil slot without raising" do
        chunk_count = described_class.new.send(:chunk_text, long_text).length
        expect(chunk_count).to be > 1

        result = described_class.new.embed([ long_text ])
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

    context "when a single input produces more than MAX_BATCH_SIZE chunks" do
      let(:huge_text) { ("word " * 32_000).strip }

      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return do |request|
          inputs = JSON.parse(request.body)["input"]
          data = inputs.each_index.map { |i| { index: i, embedding: [ 0.5, 0.5 ] } }
          { status: 200, body: { data: data }.to_json, headers: { "Content-Type" => "application/json" } }
        end
      end

      it "sub-batches the chunk list across multiple requests without raising ArgumentError" do
        chunk_count = described_class.new.send(:chunk_text, huge_text).length
        expect(chunk_count).to be > described_class::MAX_BATCH_SIZE

        expected_requests = (chunk_count.to_f / described_class::MAX_BATCH_SIZE).ceil
        expected_component = 0.5 / Math.sqrt(0.5**2 + 0.5**2)

        result = nil
        expect { result = described_class.new.embed_batch(inputs: [ huge_text ]) }.not_to raise_error

        expect(a_request(:post, embeddings_endpoint)).to have_been_made.times(expected_requests)
        expect(result.length).to eq(1)
        expect(result.first[0]).to be_within(0.0001).of(expected_component)
        expect(result.first[1]).to be_within(0.0001).of(expected_component)
      end
    end

    context "when a chunk of a long input fails to embed" do
      let(:long_text) { (("lorem ipsum dolor sit amet consectetur adipiscing elit ") * 30).strip }

      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(
          status:  200,
          body:    { data: [ { index: 0, embedding: [ 0.4, 0.3 ] } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "raises Error even though some chunks embedded successfully" do
        chunk_count = described_class.new.send(:chunk_text, long_text).length
        expect(chunk_count).to be > 1

        expect { described_class.new.embed_batch(inputs: [ long_text ]) }
          .to raise_error(Pito::Embedding::Client::Error, /missing/)
      end
    end
  end

  describe "DIMENSIONS" do
    it "is locked at 768 (matches the pgvector columns)" do
      expect(described_class::DIMENSIONS).to eq(768)
    end
  end

  # 3.0.1 full prefix adoption: every chunk is sent with the EmbeddingGemma
  # sentence-similarity prompt prepended AT THE WIRE — callers pass raw text,
  # digest raw text, and receive the sidecar's vectors untouched.
  describe "PROMPT_PREFIX wiring" do
    before do
      set_embedder_url(base_url)
      stub_request(:post, embeddings_endpoint).to_return do |request|
        inputs = JSON.parse(request.body)["input"]
        data = inputs.each_index.map { |i| { index: i, embedding: [ 1.0, 0.0 ] } }
        { status: 200, body: { data: data }.to_json, headers: { "Content-Type" => "application/json" } }
      end
    end

    it "prefixes every chunk of a multi-chunk input on the wire" do
      long_text = (("lorem ipsum dolor sit amet consectetur adipiscing elit ") * 30).strip
      described_class.new.embed([ long_text ])

      sent = []
      expect(
        a_request(:post, embeddings_endpoint).with do |req|
          sent.concat(JSON.parse(req.body)["input"])
          true
        end
      ).to have_been_made.at_least_once

      expect(sent.length).to be > 1
      sent.each { |input| expect(input).to start_with(described_class::PROMPT_PREFIX) }
    end

    it "splits chunks to the reduced budget so prefixed chunks stay inside the safety envelope" do
      expect(described_class::CHUNK_BUDGET)
        .to eq(described_class::MAX_CHARS_PER_CHUNK - described_class::PROMPT_PREFIX.length)

      long_text = (("lorem ipsum dolor sit amet consectetur adipiscing elit ") * 30).strip
      chunks = described_class.new.send(:chunk_text, long_text)
      chunks.each do |chunk|
        expect(chunk.length).to be <= described_class::CHUNK_BUDGET
        expect((described_class::PROMPT_PREFIX + chunk).length)
          .to be <= described_class::MAX_CHARS_PER_CHUNK
      end
    end

    it "never leaks the prefix into returned vectors (single short input: prefixed wire body, raw model vector back)" do
      result = described_class.new.embed([ "short input" ])
      expect(result).to eq([ [ 1.0, 0.0 ] ])

      expect(
        a_request(:post, embeddings_endpoint).with(
          body: { input: [ described_class::PROMPT_PREFIX + "short input" ] }.to_json
        )
      ).to have_been_made.once
    end
  end

  # 3.0.1 density-adaptive retry: VERIFIED prod failure was 11 conversation
  # events (dense markdown tables — pipes, digits, ids) whose CHUNK_BUDGET
  # (char) chunk still overflowed the sidecar's 512-token physical batch
  # because table content tokenizes far worse than prose. A fixed char
  # budget can't win for every density, so a chunk that 500s with the
  # sidecar's specific too-large signature gets its WHOLE input re-chunked
  # at ever-smaller budgets and retried, down to a floor.
  describe "density-adaptive chunk retry" do
    # A single unbroken "word" so #chunk_text force-splits it evenly by
    # length at any budget — mirrors the verified prod shape (one
    # CHUNK_BUDGET-sized chunk whose density trips the sidecar even though
    # it is within the character envelope).
    let(:dense_text) { "x" * described_class::CHUNK_BUDGET }

    def expected_adaptive_request_count(client_class)
      budgets = [ client_class::CHUNK_BUDGET, client_class::ADAPTIVE_RETRY_BUDGET ]
      while budgets.last > client_class::MIN_CHUNK_BUDGET
        budgets << [ budgets.last / 2, client_class::MIN_CHUNK_BUDGET ].max
      end
      budgets.length
    end

    def stub_too_large_until_quarter_budget(sent_batches)
      stub_request(:post, embeddings_endpoint).to_return do |request|
        raw = JSON.parse(request.body)["input"].map { |i| i.delete_prefix(described_class::PROMPT_PREFIX) }
        sent_batches << raw

        if raw.any? { |chunk| chunk.length >= described_class::ADAPTIVE_RETRY_BUDGET }
          { status: 500, body: "input (1589 tokens) is too large to process — current batch size: 512" }
        else
          data = raw.each_index.map { |i| { index: i, embedding: [ i + 1.0, i + 2.0 ] } }
          { status: 200, body: { data: data }.to_json, headers: { "Content-Type" => "application/json" } }
        end
      end
    end

    def expected_pooled_vector(chunk_count)
      mean = [
        (0...chunk_count).sum { |i| i + 1.0 } / chunk_count,
        (0...chunk_count).sum { |i| i + 2.0 } / chunk_count
      ]
      norm = Math.sqrt(mean.sum { |v| v**2 })
      mean.map { |v| v / norm }
    end

    context "when the default budget 500s too-large but a smaller budget fits" do
      before { set_embedder_url(base_url) }

      it "#embed re-chunks at ever-smaller budgets and pools the vectors from the retry that fit" do
        sent_batches = []
        stub_too_large_until_quarter_budget(sent_batches)

        result = described_class.new.embed([ dense_text ]).first

        expect(sent_batches.length).to eq(3)
        lengths = sent_batches.map { |batch| batch.map(&:length).max }
        expect(lengths[0]).to be > lengths[1]
        expect(lengths[1]).to be > lengths[2]
        expect(lengths[2]).to be < described_class::ADAPTIVE_RETRY_BUDGET

        expected = expected_pooled_vector(sent_batches.last.length)
        expect(result.length).to eq(2)
        result.each_with_index { |v, i| expect(v).to be_within(0.0001).of(expected[i]) }
      end

      it "#embed_batch re-chunks at ever-smaller budgets and pools the vectors from the retry that fit" do
        sent_batches = []
        stub_too_large_until_quarter_budget(sent_batches)

        result = described_class.new.embed_batch(inputs: [ dense_text ]).first

        expect(sent_batches.length).to eq(3)
        lengths = sent_batches.map { |batch| batch.map(&:length).max }
        expect(lengths[0]).to be > lengths[1]
        expect(lengths[1]).to be > lengths[2]

        expected = expected_pooled_vector(sent_batches.last.length)
        expect(result.length).to eq(2)
        result.each_with_index { |v, i| expect(v).to be_within(0.0001).of(expected[i]) }
      end
    end

    context "when the too-large failure persists all the way to MIN_CHUNK_BUDGET" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(
          status: 500,
          body:   "input (9999 tokens) is too large to process — current batch size: 512"
        )
      end

      it "#embed returns a nil slot without raising, bounded by MIN_CHUNK_BUDGET" do
        result = described_class.new.embed([ dense_text ])
        expect(result).to eq([ nil ])
        expect(a_request(:post, embeddings_endpoint))
          .to have_been_made.times(expected_adaptive_request_count(described_class))
      end

      it "#embed_batch raises Error, bounded by MIN_CHUNK_BUDGET" do
        expect { described_class.new.embed_batch(inputs: [ dense_text ]) }
          .to raise_error(Pito::Embedding::Client::Error, /missing/)
        expect(a_request(:post, embeddings_endpoint))
          .to have_been_made.times(expected_adaptive_request_count(described_class))
      end
    end

    context "when a 500 is not the too-large signature" do
      before do
        set_embedder_url(base_url)
        stub_request(:post, embeddings_endpoint).to_return(status: 500, body: "boom")
      end

      it "#embed does not adapt — a single request, nil slot" do
        result = described_class.new.embed([ dense_text ])
        expect(result).to eq([ nil ])
        expect(a_request(:post, embeddings_endpoint)).to have_been_made.once
      end

      it "#embed_batch does not adapt — a single request, raises immediately" do
        expect { described_class.new.embed_batch(inputs: [ dense_text ]) }
          .to raise_error(Pito::Embedding::Client::Error)
        expect(a_request(:post, embeddings_endpoint)).to have_been_made.once
      end
    end
  end

  describe "#healthy?" do
    let(:health_endpoint) { "#{base_url}/health" }

    context "when the URL is unconfigured" do
      before { set_embedder_url(nil) }

      it "returns false without making an HTTP request" do
        stub = stub_request(:get, %r{.*/health})
        expect(described_class.new.healthy?).to be false
        expect(stub).not_to have_been_requested
      end
    end

    context "on a 200 response" do
      before do
        set_embedder_url(base_url)
        stub_request(:get, health_endpoint).to_return(status: 200, body: "ok")
      end

      it "returns true" do
        expect(described_class.new.healthy?).to be true
      end
    end

    context "on a non-2xx response" do
      before do
        set_embedder_url(base_url)
        stub_request(:get, health_endpoint).to_return(status: 503, body: "unavailable")
      end

      it "returns false without raising" do
        expect(described_class.new.healthy?).to be false
      end
    end

    context "on a network error" do
      before do
        set_embedder_url(base_url)
        stub_request(:get, health_endpoint).to_timeout
      end

      it "returns false without raising" do
        expect(described_class.new.healthy?).to be false
      end
    end

    context "on a connection failure" do
      before do
        set_embedder_url(base_url)
        stub_request(:get, health_endpoint).to_raise(Errno::ECONNREFUSED)
      end

      it "returns false without raising" do
        expect(described_class.new.healthy?).to be false
      end
    end
  end
end
