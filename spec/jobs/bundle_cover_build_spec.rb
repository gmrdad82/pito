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

  # 2026-05-18 (live cover refresh) — after the composite is written
  # the job broadcasts two Turbo Stream `replace` events on the per-
  # bundle `"bundle_cover:<id>"` stream so /games (bundles shelf),
  # /games/:id (bundles section), and the open bundles modal swap in
  # the new cover without a page reload.
  describe "live cover refresh broadcast" do
    let(:bundle) { create(:bundle) }
    let(:stream) { "bundle_cover:#{bundle.id}" }

    before do
      allow(Composite::Builder).to receive(:new).and_return(
        instance_double(Composite::Builder, call: nil)
      )
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "broadcasts a replace of the shelf-tile cover-wrap to the bundle stream" do
      described_class.new.perform(bundle.id)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(
          stream,
          hash_including(
            target: "bundle_cover_#{bundle.id}",
            partial: "games/bundle_tile_cover",
            locals: hash_including(:bundle, :width, :height, :overflow_n)
          )
        )
    end

    it "broadcasts a replace of the modal composite wrapper to the bundle stream" do
      described_class.new.perform(bundle.id)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(
          stream,
          hash_including(
            target: "bundle_modal_composite_#{bundle.id}",
            partial: "bundles/modal_composite",
            locals: hash_including(:bundle)
          )
        )
    end

    it "uses the grid 150x200 dimensions for the shelf-tile broadcast" do
      described_class.new.perform(bundle.id)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(
          stream,
          hash_including(
            target: "bundle_cover_#{bundle.id}",
            locals: hash_including(width: 150, height: 200)
          )
        )
    end

    it "broadcasts BOTH replaces (shelf tile + modal composite)" do
      described_class.new.perform(bundle.id)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).twice
    end

    it "does not broadcast when the bundle was deleted mid-flight (no-op)" do
      described_class.new.perform(999_999)
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    it "does not broadcast when the composer raises (the rescue sits AFTER rebuild_one)" do
      # Override the outer `before` builder stub (which returns a
      # no-op double) with one that raises, so the job propagates the
      # raise out of rebuild_one BEFORE reaching the broadcast step.
      raising = instance_double(Composite::Builder)
      allow(raising).to receive(:call).and_raise(StandardError.new("boom"))
      allow(Composite::Builder).to receive(:new).and_return(raising)

      expect { described_class.new.perform(bundle.id) }
        .to raise_error(StandardError)
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
    end

    it "swallows broadcast errors (does not escape perform / does not retry)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        .and_raise(StandardError.new("redis down"))

      expect { described_class.new.perform(bundle.id) }.not_to raise_error
    end

    it "still advances the chain after a successful broadcast" do
      next_bundle = create(:bundle)
      described_class.clear

      described_class.new.perform(bundle.id, [ next_bundle.id ])

      enqueued = described_class.jobs.map { |j| j["args"] }
      expect(enqueued).to include([ next_bundle.id, [] ])
    end
  end
end
