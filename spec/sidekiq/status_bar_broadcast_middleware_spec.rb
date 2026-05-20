require "rails_helper"
require "sidekiq/api"

# Beta 4 — Phase F1 Lane A. Locks the contract of the Sidekiq server
# middleware that broadcasts queue-depth snapshots to `pito:status_bar`
# after every job runs.
#
# * Always broadcasts after the inner job, even when the job raises
#   (the `ensure` block guarantees this — failure surfaces in the next
#   broadcast's `retry` count, which is the desired TUI feedback).
# * Broadcast failures (Redis hiccup, cable backend down) are SWALLOWED
#   with a warn-level log — the middleware MUST NEVER mask a real job
#   failure or leak its own exception up the Sidekiq stack.
# * Payload follows the ADR 0017 envelope (`kind` / `payload` / `ts`)
#   with `kind: "data"` for fresh stats pushes that don't change state.
RSpec.describe StatusBarBroadcastMiddleware do
  let(:middleware) { described_class.new }
  let(:job_instance) { instance_double("SomeWorker") }
  let(:job_payload) { { "class" => "SomeWorker", "args" => [] } }
  let(:queue) { "default" }

  before do
    # Stub Sidekiq::Stats so the spec runs without a live Redis
    # accumulating jobs from previous test runs.
    stats = instance_double(Sidekiq::Stats,
                            workers_size: 3,
                            enqueued: 7,
                            retry_size: 1,
                            scheduled_size: 4)
    allow(Sidekiq::Stats).to receive(:new).and_return(stats)
  end

  it "broadcasts queue stats to `pito:status_bar` after the job runs" do
    expect(ActionCable.server).to receive(:broadcast).with(
      "pito:status_bar",
      hash_including(
        kind: "data",
        payload: hash_including(:busy, :enqueued, :retry, :scheduled),
        ts: a_kind_of(String)
      )
    )

    result = nil
    middleware.call(job_instance, job_payload, queue) { result = :job_result }

    expect(result).to eq(:job_result)
  end

  it "includes the live Sidekiq stats in the payload" do
    expect(ActionCable.server).to receive(:broadcast).with(
      "pito:status_bar",
      hash_including(
        payload: { busy: 3, enqueued: 7, retry: 1, scheduled: 4 }
      )
    )

    middleware.call(job_instance, job_payload, queue) { :ok }
  end

  it "still broadcasts when the job raises and re-raises the original error" do
    expect(ActionCable.server).to receive(:broadcast).with(
      "pito:status_bar",
      hash_including(kind: "data")
    )

    expect {
      middleware.call(job_instance, job_payload, queue) { raise StandardError, "boom" }
    }.to raise_error(StandardError, "boom")
  end

  it "swallows broadcast failures and logs a warning (does not raise)" do
    allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "redis exploded")
    expect(Rails.logger).to receive(:warn).with(/StatusBarBroadcastMiddleware failed.*redis exploded/)

    expect {
      middleware.call(job_instance, job_payload, queue) { :ok }
    }.not_to raise_error
  end

  it "still completes the inner job result when the broadcast fails" do
    allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "redis exploded")
    allow(Rails.logger).to receive(:warn)

    result = nil
    middleware.call(job_instance, job_payload, queue) { result = :inner_done }

    expect(result).to eq(:inner_done)
  end
end
