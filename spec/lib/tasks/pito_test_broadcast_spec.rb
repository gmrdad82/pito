# FB-test-infra (2026-05-22). Lock the dev/test broadcast rake task
# contract. Two surfaces:
#
#   pito:test:broadcast_sidekiq[busy,enqueued,retry_count]
#     → Pito::CableBroadcaster.broadcast_status_bar(
#         { busy:, enqueued:, retry: }, kind: :sidekiq)
#
#   pito:test:broadcast_notifications[future_count]
#     → Pito::CableBroadcaster.broadcast_status_bar(
#         { future_count: }, kind: :notifications)
#
# `broadcast_sync` was intentionally dropped — sync state is no longer
# externally settable. The sync indicator pulses on ANY cable activity
# via the `tui:cable-activity` event fanned out by the parent
# `tui-status-bar` controller. This spec asserts the task is GONE so
# nobody accidentally reintroduces an externally-settable sync path.
require "rails_helper"
require "rake"

RSpec.describe "lib/tasks/pito_test_broadcast.rake" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_test_broadcast",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  # Helper: silence rake `puts` output for cleaner test runs.
  def silence_stream(stream)
    old_stream = stream.dup
    stream.reopen(File::NULL)
    yield
  ensure
    stream.reopen(old_stream)
    old_stream.close
  end

  describe "pito:test:broadcast_sidekiq" do
    let(:task) { Rake::Task["pito:test:broadcast_sidekiq"] }

    it "is defined" do
      expect(task).to be_present
    end

    it "broadcasts via Pito::CableBroadcaster with kind: :sidekiq + the canonical payload keys" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_status_bar)
        .with({ busy: 3, enqueued: 5, retry: 2 }, kind: :sidekiq)

      silence_stream($stdout) do
        task.execute(Rake::TaskArguments.new(
          %i[busy enqueued retry_count],
          [ "3", "5", "2" ]
        ))
      end
    end

    it "coerces missing args to 0 (busy/enqueued/retry default to integer 0)" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_status_bar)
        .with({ busy: 0, enqueued: 0, retry: 0 }, kind: :sidekiq)

      silence_stream($stdout) do
        task.execute(Rake::TaskArguments.new(
          %i[busy enqueued retry_count],
          [ nil, nil, nil ]
        ))
      end
    end
  end

  describe "pito:test:broadcast_notifications" do
    let(:task) { Rake::Task["pito:test:broadcast_notifications"] }

    it "is defined" do
      expect(task).to be_present
    end

    it "broadcasts via Pito::CableBroadcaster with kind: :notifications + future_count payload" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_status_bar)
        .with({ future_count: 4 }, kind: :notifications)

      silence_stream($stdout) do
        task.execute(Rake::TaskArguments.new(
          %i[future_count],
          [ "4" ]
        ))
      end
    end

    it "coerces a missing future_count to 0" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_status_bar)
        .with({ future_count: 0 }, kind: :notifications)

      silence_stream($stdout) do
        task.execute(Rake::TaskArguments.new(%i[future_count], [ nil ]))
      end
    end
  end

  describe "pito:test:broadcast_sync (DROPPED 2026-05-22)" do
    # The task was removed when the sync indicator was rewired to
    # pulse on any cable activity. External callers must not be able
    # to set sync state directly. If this assertion ever flips green
    # (task exists), someone re-introduced an externally-settable
    # sync surface.
    it "is NOT defined" do
      expect(Rake::Task.task_defined?("pito:test:broadcast_sync")).to be false
    end
  end
end
