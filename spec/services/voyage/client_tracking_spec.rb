# frozen_string_literal: true

require "rails_helper"

# Pito::Stack instrumentation at the Voyage chokepoint.
RSpec.describe Voyage::Client, type: :service do
  before do
    allow(Pito::Credentials).to receive(:voyage_api_key).and_return("test-key")
    stub_request(:post, "https://api.voyageai.com/v1/embeddings").to_return do |request|
      inputs = JSON.parse(request.body)["input"]
      rows = Array(inputs).each_index.map { |i| { index: i, embedding: Array.new(1024, 0.1) } }
      { status: 200, body: { data: rows }.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end

  it "records a voyage ApiRequest on embed" do
    expect { described_class.new.embed([ "hello" ]) }
      .to change { ApiRequest.voyage.count }.by(1)
  end

  it "records a voyage ApiRequest on embed_batch" do
    expect { described_class.new.embed_batch(inputs: [ "a", "b" ]) }
      .to change { ApiRequest.voyage.count }.by(1)
  end
end
