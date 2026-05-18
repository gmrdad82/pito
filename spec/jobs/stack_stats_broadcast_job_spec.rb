require "rails_helper"

RSpec.describe StackStatsBroadcastJob, type: :job do
  before { allow(StackStats::Broadcaster).to receive(:broadcast!) }

  it "is enqueued on the :default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "calls StackStats::Broadcaster.broadcast! exactly once" do
    expect(StackStats::Broadcaster).to receive(:broadcast!).once

    described_class.new.perform
  end

  it "does NOT re-enqueue itself (one-shot trailing-edge — would loop forever)" do
    clear_enqueued_jobs

    described_class.new.perform

    expect(enqueued_jobs.select { |j| j[:job] == described_class }).to be_empty
  end

  it "enqueues via ActiveJob" do
    clear_enqueued_jobs

    expect {
      described_class.perform_later
    }.to have_enqueued_job(described_class)
  end

  it "supports the wait option used by the trailing-edge callers (set wait: 1.second)" do
    clear_enqueued_jobs

    expect {
      described_class.set(wait: 1.second).perform_later
    }.to have_enqueued_job(described_class).at(a_value_within(2.seconds).of(1.second.from_now))
  end
end
