require "rails_helper"

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
    let(:bundle) { create(:bundle, bundle_type: :custom) }

    it "invokes Composite::Builder for the bundle" do
      builder = instance_double(Composite::Builder, call: nil)
      allow(Composite::Builder).to receive(:new).and_return(builder)

      described_class.new.perform(bundle.id)
      expect(builder).to have_received(:call).with(bundle)
    end

    it "no-ops gracefully when the bundle does not exist" do
      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    it "stamps last_error and re-raises on Composite::TileFetchError" do
      allow_any_instance_of(Composite::Builder).to receive(:call)
        .and_raise(Composite::TileFetchError.new("CDN 404"))

      expect { described_class.new.perform(bundle.id) }
        .to raise_error(Composite::TileFetchError)
      expect(bundle.reload.last_error).to include("tile fetch")
      expect(bundle.last_error).to include("CDN 404")
    end

    it "stamps last_error and re-raises on generic StandardError" do
      allow_any_instance_of(Composite::Builder).to receive(:call)
        .and_raise(StandardError.new("boom"))

      expect { described_class.new.perform(bundle.id) }
        .to raise_error(StandardError)
      expect(bundle.reload.last_error).to include("build")
      expect(bundle.last_error).to include("boom")
    end
  end
end
