require "rails_helper"
require "sidekiq/api"

# Beta 4 — Phase F1 Lane A. Locks the contract of the Sidekiq server
# middleware that broadcasts queue-depth snapshots to `pito:status_bar`
# after every job runs.
#
# * Fires a START broadcast BEFORE `yield` (FB-153) so the TST paints
#   `b1` while the work is in flight, and another (END) broadcast in
#   `ensure` so the post-yield snapshot lands too.
# * Always broadcasts in `ensure`, even when the job raises (failure
#   surfaces in the next broadcast's `retry` count, which is the
#   desired TUI feedback).
# * Broadcast failures (Redis hiccup, cable backend down) are SWALLOWED
#   with a warn-level log — the middleware MUST NEVER mask a real job
#   failure or leak its own exception up the Sidekiq stack.
# * Payload follows the ADR 0017 envelope (`kind` / `payload` / `ts`)
#   with `kind: "data"` for fresh stats pushes that don't change state.
# * Payload's `sync_state` (FB-153) tracks `AppSetting.reindex_running?`
#   so the TST sync indicator flips amber during a reindex.
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
    allow(AppSetting).to receive(:reindex_running?).and_return(false)
    allow(StatusBarBroadcastJob).to receive_message_chain(:set, :perform_later)
  end

  it "broadcasts queue stats to `pito:status_bar` around the job (START + END)" do
    expect(ActionCable.server).to receive(:broadcast).with(
      "pito:status_bar",
      hash_including(
        kind: "data",
        payload: hash_including(:busy, :enqueued, :retry, :scheduled, :sync_state),
        ts: a_kind_of(String)
      )
    ).at_least(:twice)

    result = nil
    middleware.call(job_instance, job_payload, queue) { result = :job_result }

    expect(result).to eq(:job_result)
  end

  it "includes the live Sidekiq stats in the payload" do
    expect(ActionCable.server).to receive(:broadcast).with(
      "pito:status_bar",
      hash_including(
        payload: hash_including(busy: 3, enqueued: 7, retry: 1, scheduled: 4)
      )
    ).at_least(:once)

    middleware.call(job_instance, job_payload, queue) { :ok }
  end

  it "includes sync_state: 'syncing' when AppSetting.reindex_running? is true" do
    allow(AppSetting).to receive(:reindex_running?).and_return(true)

    expect(ActionCable.server).to receive(:broadcast).with(
      "pito:status_bar",
      hash_including(payload: hash_including(sync_state: "syncing"))
    ).at_least(:once)

    middleware.call(job_instance, job_payload, queue) { :ok }
  end

  it "includes sync_state: 'idle' when AppSetting.reindex_running? is false" do
    expect(ActionCable.server).to receive(:broadcast).with(
      "pito:status_bar",
      hash_including(payload: hash_including(sync_state: "idle"))
    ).at_least(:once)

    middleware.call(job_instance, job_payload, queue) { :ok }
  end

  it "still broadcasts when the job raises and re-raises the original error" do
    expect(ActionCable.server).to receive(:broadcast).with(
      "pito:status_bar",
      hash_including(kind: "data")
    ).at_least(:once)

    expect {
      middleware.call(job_instance, job_payload, queue) { raise StandardError, "boom" }
    }.to raise_error(StandardError, "boom")
  end

  it "swallows broadcast failures and logs a warning (does not raise)" do
    allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "redis exploded")
    expect(Rails.logger).to receive(:warn).with(/StatusBarBroadcastMiddleware failed.*redis exploded/).at_least(:once)

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

  describe "self-skip guard (FB-171)" do
    it "skips the START broadcast when the job class is StatusBarBroadcastJob (raw Sidekiq form)" do
      payload = { "class" => "StatusBarBroadcastJob", "args" => [] }

      # Only the END broadcast (from ensure) should fire — not 2x.
      expect(ActionCable.server).to receive(:broadcast).once

      middleware.call(job_instance, payload, queue) { :ok }
    end

    it "skips the START broadcast when wrapped by ActiveJob's JobWrapper" do
      payload = {
        "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
        "wrapped" => "StatusBarBroadcastJob",
        "args" => []
      }

      expect(ActionCable.server).to receive(:broadcast).once

      middleware.call(job_instance, payload, queue) { :ok }
    end

    it "does NOT schedule another trailing-edge job when the current job IS StatusBarBroadcastJob (no infinite loop)" do
      payload = {
        "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
        "wrapped" => "StatusBarBroadcastJob",
        "args" => []
      }
      allow(ActionCable.server).to receive(:broadcast)

      expect(StatusBarBroadcastJob).not_to receive(:set)

      middleware.call(job_instance, payload, queue) { :ok }
    end

    it "DOES schedule a trailing-edge job for a regular wrapped ActiveJob" do
      payload = {
        "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
        "wrapped" => "MeilisearchReindexJob",
        "args" => []
      }
      allow(ActionCable.server).to receive(:broadcast)
      set_proxy = double("set_proxy", perform_later: true)

      expect(StatusBarBroadcastJob).to receive(:set).with(wait: 1.second).and_return(set_proxy)

      middleware.call(job_instance, payload, queue) { :ok }
    end
  end
end
