require "rails_helper"

RSpec.describe CalendarDerivationJob, type: :job do
  it "calls Pito::Calendar::Derivation#sync! with the host class + id" do
    video = create(:video)
    expect(Pito::Calendar::Derivation).to receive(:sync!).with(an_instance_of(Video))
    described_class.new.perform("Video", video.id)
  end

  it "is a no-op when the host row is missing" do
    expect(Pito::Calendar::Derivation).not_to receive(:sync!)
    expect {
      described_class.new.perform("Video", 999_999_999)
    }.not_to raise_error
  end

  it "enqueues onto the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end
end
