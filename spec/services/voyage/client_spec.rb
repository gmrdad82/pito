require "rails_helper"

RSpec.describe Voyage::Client do
  let(:client) { described_class.new }
  let(:api_key) { "vk_test_stubbed" }
  let(:url) { described_class::VOYAGE_URL }

  def stub_voyage_credentials_key(value)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:voyage, :api_key).and_return(value)
  end

  before { stub_voyage_credentials_key(api_key) }

  describe "#embed" do
    it "returns the embedding for a single input on a 200 response" do
      vector = Array.new(1024) { 0.5 }
      body = { data: [ { index: 0, embedding: vector } ] }.to_json
      WebMock.stub_request(:post, url).to_return(
        status: 200,
        body: body,
        headers: { "Content-Type" => "application/json" }
      )

      result = client.embed([ "hello world" ])

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first).to eq(vector)
    end

    it "returns [] for an empty input list (no HTTP call)" do
      expect(client.embed([])).to eq([])
    end

    it "returns an array of nils when the API key is blank (no HTTP call)" do
      stub_voyage_credentials_key("")

      result = client.embed([ "a", "b", "c" ])

      expect(result).to eq([ nil, nil, nil ])
    end

    it "returns an array of nils when every input is blank (no HTTP call)" do
      result = client.embed([ "", "   " ])

      expect(result).to eq([ nil, nil ])
    end

    it "returns nil slots on a non-2xx response (forgiving contract)" do
      WebMock.stub_request(:post, url)
        .to_return(status: 500, body: "boom", headers: { "Content-Type" => "text/plain" })

      result = client.embed([ "a" ])

      expect(result).to eq([ nil ])
    end

    it "returns nil slots when the network raises (forgiving contract)" do
      WebMock.stub_request(:post, url).to_raise(StandardError.new("network"))

      result = client.embed([ "a" ])

      expect(result).to eq([ nil ])
    end
  end

  describe "#embed_batch" do
    it "returns the embeddings in input order on a 200 response" do
      body = {
        data: [
          { index: 0, embedding: [ 1.0 ] },
          { index: 1, embedding: [ 2.0 ] },
          { index: 2, embedding: [ 3.0 ] }
        ]
      }.to_json
      WebMock.stub_request(:post, url).to_return(
        status: 200,
        body: body,
        headers: { "Content-Type" => "application/json" }
      )

      result = client.embed_batch(inputs: [ "a", "b", "c" ])

      expect(result).to eq([ [ 1.0 ], [ 2.0 ], [ 3.0 ] ])
    end

    it "reorders a reordered response by the index field" do
      body = {
        data: [
          { index: 2, embedding: [ 3.0 ] },
          { index: 0, embedding: [ 1.0 ] },
          { index: 1, embedding: [ 2.0 ] }
        ]
      }.to_json
      WebMock.stub_request(:post, url).to_return(
        status: 200,
        body: body,
        headers: { "Content-Type" => "application/json" }
      )

      result = client.embed_batch(inputs: [ "a", "b", "c" ])

      expect(result).to eq([ [ 1.0 ], [ 2.0 ], [ 3.0 ] ])
    end

    it "raises ArgumentError when inputs.size exceeds MAX_BATCH_SIZE (128)" do
      inputs = Array.new(described_class::MAX_BATCH_SIZE + 1) { |i| "input-#{i}" }

      expect {
        client.embed_batch(inputs: inputs)
      }.to raise_error(ArgumentError, /Voyage embed batch limit/)
    end

    it "returns [] for an empty input list (no HTTP call)" do
      expect(client.embed_batch(inputs: [])).to eq([])
    end

    it "raises Voyage::Client::Error when the API key is missing" do
      stub_voyage_credentials_key("")

      expect {
        client.embed_batch(inputs: [ "a" ])
      }.to raise_error(described_class::Error, /API key not configured/)
    end

    it "raises Voyage::Client::Error with status + body on a non-2xx response" do
      WebMock.stub_request(:post, url).to_return(
        status: 503,
        body: "service unavailable",
        headers: { "Content-Type" => "text/plain" }
      )

      expect {
        client.embed_batch(inputs: [ "a" ])
      }.to raise_error(described_class::Error, /503.*service unavailable/m)
    end

    it "raises Voyage::Client::Error on network failure" do
      WebMock.stub_request(:post, url).to_raise(SocketError.new("dns down"))

      expect {
        client.embed_batch(inputs: [ "a" ])
      }.to raise_error(described_class::Error, /Voyage embed_batch failed/)
    end

    it "raises Voyage::Client::Error when the response is missing the data array" do
      WebMock.stub_request(:post, url).to_return(
        status: 200,
        body: { foo: "bar" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      expect {
        client.embed_batch(inputs: [ "a" ])
      }.to raise_error(described_class::Error, /missing 'data' array/)
    end

    it "raises Voyage::Client::Error when a row is missing its index field" do
      body = { data: [ { embedding: [ 1.0 ] } ] }.to_json
      WebMock.stub_request(:post, url).to_return(
        status: 200,
        body: body,
        headers: { "Content-Type" => "application/json" }
      )

      expect {
        client.embed_batch(inputs: [ "a" ])
      }.to raise_error(described_class::Error, /missing 'index' field/)
    end

    it "raises Voyage::Client::Error when the response is missing an embedding slot" do
      body = { data: [ { index: 0, embedding: [ 1.0 ] } ] }.to_json
      WebMock.stub_request(:post, url).to_return(
        status: 200,
        body: body,
        headers: { "Content-Type" => "application/json" }
      )

      expect {
        client.embed_batch(inputs: [ "a", "b" ])
      }.to raise_error(described_class::Error, /missing embeddings for input indices/)
    end
  end
end
