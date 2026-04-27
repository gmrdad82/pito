require "rails_helper"

RSpec.describe ReindexAllJob, type: :job do
  let(:engine) { instance_double(Search::MeilisearchEngine) }

  before do
    allow(Search).to receive(:engine).and_return(engine)
  end

  it "reindexes channels and videos" do
    expect(engine).to receive(:reindex_all).with(Channel)
    expect(engine).to receive(:reindex_all).with(Video)
    described_class.perform_now
  end

  it "enqueues via ActiveJob" do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
  end
end
