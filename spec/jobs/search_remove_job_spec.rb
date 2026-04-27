require "rails_helper"

RSpec.describe SearchRemoveJob, type: :job do
  let(:engine) { Search::MeilisearchEngine.new }
  let(:client) { engine.instance_variable_get(:@client) }
  let(:mock_index) { instance_double("MeiliSearch::Index") }

  before do
    allow(Search).to receive(:engine).and_return(engine)
    allow(client).to receive(:index).and_return(mock_index)
  end

  it "removes the document from Meilisearch" do
    expect(mock_index).to receive(:delete_document).with(42)
    described_class.perform_now("Channel", 42, index_name: "channels_test")
  end

  it "does not raise when document not found" do
    allow(mock_index).to receive(:delete_document).and_raise(
      Meilisearch::ApiError.new(404, "not found", {})
    )
    expect { described_class.perform_now("Channel", 999, index_name: "channels_test") }.not_to raise_error
  end
end
