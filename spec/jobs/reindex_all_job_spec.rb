require "rails_helper"

RSpec.describe ReindexAllJob, type: :job do
  let(:engine) { instance_double(Search::MeilisearchEngine) }

  before do
    allow(Search).to receive(:engine).and_return(engine)
    allow(engine).to receive(:reindex_all)
    # The deliberate testing-visibility sleep is bypassed in specs —
    # the constant comment in the job calls out that it is FOR LOCAL
    # TESTING VISIBILITY and a value of `0` skips the pause. Stub the
    # method directly so specs don't depend on the constant value.
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  it "reindexes channels and videos" do
    expect(engine).to receive(:reindex_all).with(Channel)
    expect(engine).to receive(:reindex_all).with(Video)
    described_class.perform_now
  end

  it "enqueues via ActiveJob" do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
  end

  # Phase 32 follow-up (2026-05-16) — three-layer reindex lock.
  describe "ensure-block cleanup" do
    it "clears the AppSetting reindex lock after a successful run" do
      pending "validated manually first; spec fills in after the operator " \
              "confirms the lock + broadcast round-trip works end to end"
      raise "pending placeholder"
    end

    it "clears the AppSetting reindex lock even when the engine raises" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "broadcasts a Turbo Stream replace to `reindex_status` " \
       "targeting `voyage_section`" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "swallows broadcast errors so they never escape the ensure block" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end

  describe "deliberate testing-visibility sleep" do
    it "sleeps for REINDEX_SLEEP_SECONDS at the top of perform " \
       "(set the constant to 0 for production)" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end

  describe "Sidekiq uniqueness intent declaration" do
    it "declares `lock: :until_executed, on_conflict: :log` via " \
       "sidekiq_options (no-op without Sidekiq Enterprise / " \
       "sidekiq-unique-jobs; DB flag is the real safety net)" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end
end
