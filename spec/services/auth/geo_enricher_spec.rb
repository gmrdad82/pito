require "rails_helper"

RSpec.describe Auth::GeoEnricher do
  before do
    described_class.reset_deferred!
    described_class.reset_reader_for_test!
  end

  describe ".call" do
    context "happy path (MaxMind reader available)" do
      let(:fake_data) do
        {
          "city" => { "names" => { "en" => "Bucharest" } },
          "subdivisions" => [ { "names" => { "en" => "Bucharest" } } ],
          "country" => { "iso_code" => "RO" }
        }
      end

      before do
        # Skip the gem-presence + file-presence gate so the spec
        # exercises the lookup path without a real .mmdb on disk.
        allow(described_class).to receive(:db_available?).and_return(true)
        allow(described_class).to receive(:lookup).and_return(
          city: "Bucharest", region: "Bucharest", country: "RO"
        )
      end

      it "returns city, region, country for a known IP" do
        result = described_class.call("1.2.3.4")
        expect(result).to eq(city: "Bucharest", region: "Bucharest", country: "RO")
      end

      it "does not flip the deferred flag on a fast successful lookup" do
        described_class.call("1.2.3.4")
        expect(described_class.deferred?).to be false
      end
    end

    context "sad path: DB unavailable" do
      before do
        allow(described_class).to receive(:db_available?).and_return(false)
      end

      it "returns the empty geo hash" do
        expect(described_class.call("1.2.3.4")).to eq(city: nil, region: nil, country: nil)
      end

      it "sets the deferred flag so the logger enqueues the backfill job" do
        described_class.call("1.2.3.4")
        expect(described_class.deferred?).to be true
      end

      it "logs a warning-level note (info-level message)" do
        expect(Rails.logger).to receive(:info).with(/geo db unavailable/)
        described_class.call("1.2.3.4")
      end
    end

    context "sad path: unknown IP" do
      before do
        allow(described_class).to receive(:db_available?).and_return(true)
        allow(described_class).to receive(:lookup).and_return(
          described_class::EMPTY.dup
        )
      end

      it "returns the empty geo hash" do
        expect(described_class.call("9.9.9.9")).to eq(city: nil, region: nil, country: nil)
      end

      it "does NOT flip the deferred flag (the backfill job would also miss)" do
        described_class.call("9.9.9.9")
        expect(described_class.deferred?).to be false
      end
    end

    context "edge: lookup over time budget" do
      before do
        allow(described_class).to receive(:db_available?).and_return(true)
        # Force the monotonic clock to step forward past the budget.
        @times = [ 0.0, described_class::MAX_LOOKUP_MS + 1.0 ]
        allow(described_class).to receive(:monotonic_ms) { @times.shift }
        allow(described_class).to receive(:lookup).and_return(
          city: "Berlin", region: "Berlin", country: "DE"
        )
      end

      it "still returns the data" do
        result = described_class.call("1.2.3.4")
        expect(result[:country]).to eq("DE")
      end

      it "sets the deferred flag so the row is async-refreshed" do
        described_class.call("1.2.3.4")
        expect(described_class.deferred?).to be true
      end
    end

    context "sad path: enricher exception" do
      before do
        allow(described_class).to receive(:db_available?).and_return(true)
        allow(described_class).to receive(:lookup).and_raise(StandardError, "boom")
      end

      it "returns the empty geo hash" do
        expect(described_class.call("1.2.3.4")).to eq(city: nil, region: nil, country: nil)
      end

      it "sets the deferred flag" do
        described_class.call("1.2.3.4")
        expect(described_class.deferred?).to be true
      end
    end

    context "flaw: no outbound HTTP" do
      it "never reaches the network on the synchronous path" do
        # WebMock is configured to disable_net_connect! in rails_helper.
        # Calling with a missing DB must return empty silently, not raise.
        allow(described_class).to receive(:db_available?).and_return(false)
        expect { described_class.call("1.2.3.4") }.not_to raise_error
      end
    end

    context "nil input" do
      it "returns the empty geo hash without raising" do
        expect(described_class.call(nil)).to eq(city: nil, region: nil, country: nil)
      end
    end
  end

  describe ".deferred? / .reset_deferred!" do
    it "starts false" do
      described_class.reset_deferred!
      expect(described_class.deferred?).to be false
    end

    it "can be reset" do
      described_class.defer!("manual")
      expect(described_class.deferred?).to be true
      described_class.reset_deferred!
      expect(described_class.deferred?).to be false
    end
  end
end
