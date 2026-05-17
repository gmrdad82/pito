require "rails_helper"

# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — `BundleCoverBuild`
# Sidekiq job spec. After the 2026-05-17 simplification the job no
# longer stamps `last_error` (the column is gone); raises propagate to
# Sidekiq's retry machinery unchanged. The job also gained sequential
# chain support — accepts an optional `remaining_chain` tail.
RSpec.describe BundleCoverBuild, type: :job do
  describe "Sidekiq options" do
    it "is enqueued on the :default queue" do
      described_class.clear
      described_class.perform_async(123)
      expect(described_class.jobs.last["queue"]).to eq("default")
    end

    it "retries up to 5 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end
  end

  describe "#perform" do
    let(:bundle) { create(:bundle) }

    it "invokes Composite::Builder for the bundle" do
      builder = instance_double(Composite::Builder, call: nil)
      allow(Composite::Builder).to receive(:new).and_return(builder)

      described_class.new.perform(bundle.id)
      expect(builder).to have_received(:call).with(bundle)
    end

    it "no-ops gracefully when the bundle does not exist (single)" do
      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it "advances the chain even when the head bundle is missing" do
      next_bundle = create(:bundle)
      builder = instance_double(Composite::Builder, call: nil)
      allow(Composite::Builder).to receive(:new).and_return(builder)
      described_class.clear

      described_class.new.perform(999_999, [ next_bundle.id ])

      enqueued_args = described_class.jobs.map { |j| j["args"] }
      expect(enqueued_args).to include([ next_bundle.id, [] ])
    end

    it "re-raises on Composite::TileFetchError (no last_error stamp)" do
      allow_any_instance_of(Composite::Builder).to receive(:call)
        .and_raise(Composite::TileFetchError.new("CDN 404"))

      expect { described_class.new.perform(bundle.id) }
        .to raise_error(Composite::TileFetchError)
    end

    it "re-raises on generic StandardError (no last_error stamp)" do
      allow_any_instance_of(Composite::Builder).to receive(:call)
        .and_raise(StandardError.new("boom"))

      expect { described_class.new.perform(bundle.id) }
        .to raise_error(StandardError)
    end

    it "breaks the chain when the composer raises" do
      next_bundle = create(:bundle)
      allow_any_instance_of(Composite::Builder).to receive(:call)
        .and_raise(StandardError.new("boom"))
      described_class.clear

      expect {
        described_class.new.perform(bundle.id, [ next_bundle.id ])
      }.to raise_error(StandardError)

      enqueued = described_class.jobs.map { |j| j["args"] }
      expect(enqueued).not_to include([ next_bundle.id, [] ])
    end
  end

  describe "sequential chain support" do
    it "enqueues the next bundle on success" do
      a = create(:bundle)
      b = create(:bundle)
      c = create(:bundle)
      builder = instance_double(Composite::Builder, call: nil)
      allow(Composite::Builder).to receive(:new).and_return(builder)
      described_class.clear

      described_class.new.perform(a.id, [ b.id, c.id ])

      enqueued = described_class.jobs.map { |j| j["args"] }
      expect(enqueued).to include([ b.id, [ c.id ] ])
    end

    it "terminates the chain when the tail is empty" do
      a = create(:bundle)
      builder = instance_double(Composite::Builder, call: nil)
      allow(Composite::Builder).to receive(:new).and_return(builder)
      described_class.clear

      described_class.new.perform(a.id, [])
      expect(described_class.jobs).to be_empty
    end

    it "accepts nil as the tail and treats it as empty" do
      a = create(:bundle)
      builder = instance_double(Composite::Builder, call: nil)
      allow(Composite::Builder).to receive(:new).and_return(builder)
      described_class.clear

      described_class.new.perform(a.id, nil)
      expect(described_class.jobs).to be_empty
    end
  end
end
