require "rails_helper"

RSpec.describe SearchIndexJob, type: :job do
  let(:video) { create(:video) }
  let(:engine) { instance_double(Search::MeilisearchEngine) }

  before do
    allow(Search).to receive(:engine).and_return(engine)
  end

  it "indexes the record" do
    expect(engine).to receive(:index).with(video)
    described_class.perform_now("Video", video.id)
  end

  it "does nothing if record not found" do
    expect(engine).not_to receive(:index)
    described_class.perform_now("Video", 999_999)
  end

  it "enqueues via ActiveJob" do
    # video creation already enqueues one job via after_commit, so clear first
    video
    clear_enqueued_jobs
    expect {
      described_class.perform_later("Video", video.id)
    }.to have_enqueued_job(described_class).exactly(:once)
  end
end
