require "rails_helper"

RSpec.describe SearchIndexJob, type: :job do
  let(:channel) { create(:channel, title: "test channel") }
  let(:engine) { instance_double(Search::MeilisearchEngine) }

  before do
    allow(Search).to receive(:engine).and_return(engine)
  end

  it "indexes the record" do
    expect(engine).to receive(:index).with(channel)
    described_class.perform_now("Channel", channel.id)
  end

  it "does nothing if record not found" do
    expect(engine).not_to receive(:index)
    described_class.perform_now("Channel", 999_999)
  end

  it "enqueues via ActiveJob" do
    # channel creation already enqueues one job via after_commit, so clear first
    channel
    clear_enqueued_jobs
    expect {
      described_class.perform_later("Channel", channel.id)
    }.to have_enqueued_job(described_class).exactly(:once)
  end
end
