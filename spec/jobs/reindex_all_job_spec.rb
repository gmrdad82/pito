require "rails_helper"

RSpec.describe ReindexAllJob, type: :job do
  before do
    # The deliberate testing-visibility sleep is bypassed in specs —
    # the constant comment in the job calls out that it is FOR LOCAL
    # TESTING VISIBILITY and a value of `0` skips the pause. Stub the
    # method directly so specs don't depend on the constant value.
    allow_any_instance_of(described_class).to receive(:sleep)
    allow(StackStats::Broadcaster).to receive(:broadcast!)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "ActiveJob plumbing" do
    it "is enqueued on the :search queue" do
      expect(described_class.new.queue_name).to eq("search")
    end

    it "enqueues via ActiveJob" do
      clear_enqueued_jobs
      expect { described_class.perform_later }.to have_enqueued_job(described_class)
    end
  end

  describe "#perform" do
    it "enqueues a BulkVoyageIndexJob for the games corpus" do
      clear_enqueued_jobs

      described_class.new.perform

      enqueued = enqueued_jobs.select { |j| j[:job] == BulkVoyageIndexJob }
      expect(enqueued.map { |j| j[:args] }.flatten).to include(hash_including("corpus" => "games"))
    end

    it "enqueues a BulkVoyageIndexJob for the bundles corpus when the bundles table exists" do
      clear_enqueued_jobs

      described_class.new.perform

      enqueued = enqueued_jobs.select { |j| j[:job] == BulkVoyageIndexJob }
      expect(enqueued.map { |j| j[:args] }.flatten).to include(hash_including("corpus" => "bundles"))
    end

    it "does NOT iterate the legacy [Channel, Video] corpus loop (the EY fix)" do
      # If the old loop were still alive, this spec would raise
      # `NoMethodError: undefined method 'searchable_fields' for class Channel`
      # because neither model includes Searchable in beta 3.
      expect { described_class.new.perform }.not_to raise_error
    end

    it "enqueues exactly 2 BulkVoyageIndexJobs (games + bundles)" do
      clear_enqueued_jobs

      described_class.new.perform

      enqueued = enqueued_jobs.select { |j| j[:job] == BulkVoyageIndexJob }
      expect(enqueued.length).to eq(2)
    end
  end

  describe "broadcasting" do
    it "broadcasts an immediate stack-stats snapshot at start" do
      # broadcast! is called at both start AND ensure — verify "at start" via at_least(:twice)
      expect(StackStats::Broadcaster).to receive(:broadcast!).at_least(:twice)

      described_class.new.perform
    end

    it "broadcasts an immediate stack-stats snapshot in the ensure block" do
      expect(StackStats::Broadcaster).to receive(:broadcast!).at_least(:once)

      described_class.new.perform
    end

    it "schedules StackStatsBroadcastJob (delayed trailing-edge broadcast) in ensure" do
      clear_enqueued_jobs

      described_class.new.perform

      expect(enqueued_jobs.map { |j| j[:job] }).to include(StackStatsBroadcastJob)
    end

    it "broadcasts a Turbo Stream replace targeting voyage_section in `reindex_status`" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        .with("reindex_status", target: "voyage_section", partial: "settings/voyage_section")

      described_class.new.perform
    end

    it "swallows Turbo broadcast errors (never escape the ensure block)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "redis down")

      expect { described_class.new.perform }.not_to raise_error
    end
  end

  describe "ensure-block cleanup" do
    it "clears the AppSetting reindex lock after a successful run" do
      AppSetting.start_reindex!

      described_class.new.perform

      expect(AppSetting.reindex_running?).to eq(false)
    end

    it "clears the AppSetting reindex lock even when broadcasting at start raises" do
      AppSetting.start_reindex!
      # Cause broadcaster start-call to raise — the ensure block must still clear the lock.
      call_count = 0
      allow(StackStats::Broadcaster).to receive(:broadcast!) do
        call_count += 1
        raise StandardError, "broadcast failed" if call_count == 1
      end

      expect { described_class.new.perform }.to raise_error(StandardError)

      expect(AppSetting.reindex_running?).to eq(false)
    end
  end

  describe "Sidekiq uniqueness intent declaration" do
    it "declares lock + on_conflict via sidekiq_options" do
      opts = described_class.sidekiq_options
      expect(opts["lock"]).to eq(:until_executed)
      expect(opts["on_conflict"]).to eq(:log)
    end
  end
end
