require "rails_helper"

# Pure-Ruby helper, no DB. Coverage moved from
# `spec/models/video_viewer_time_bucket_spec.rb` per the P26 reviewer
# concern 5 (resolve_iana does not belong on the AR model).
RSpec.describe Pito::TimeZone do
  describe ".resolve_iana" do
    it "passes IANA names through" do
      expect(described_class.resolve_iana("Europe/Bucharest")).to eq("Europe/Bucharest")
    end

    it "resolves Rails-friendly aliases to IANA" do
      result = described_class.resolve_iana("Eastern Time (US & Canada)")
      expect(result).to eq("America/New_York")
    end

    it "passes ActiveSupport::TimeZone instances through" do
      tz = ActiveSupport::TimeZone["Europe/Bucharest"]
      expect(described_class.resolve_iana(tz)).to eq("Europe/Bucharest")
    end

    it "falls back to Etc/UTC for nil-ish input" do
      expect(described_class.resolve_iana(nil)).to eq("Etc/UTC")
    end

    it "passes symbol input through the string branch" do
      expect(described_class.resolve_iana(:"Europe/Bucharest")).to eq("Europe/Bucharest")
    end

    it "echoes back an unrecognized string (defensive — Postgres rejects bad zones at query time)" do
      expect(described_class.resolve_iana("Nowhere/Place")).to eq("Nowhere/Place")
    end
  end
end
