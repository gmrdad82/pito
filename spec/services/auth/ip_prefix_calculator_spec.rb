require "rails_helper"

RSpec.describe Auth::IpPrefixCalculator do
  describe ".call" do
    it "happy: IPv4 → /24" do
      expect(described_class.call("1.2.3.4")).to eq("1.2.3.0/24")
    end

    it "happy: IPv6 → /64" do
      expect(described_class.call("2001:db8::1")).to eq("2001:db8::/64")
    end

    it "edge: loopback IPv4 → 127.0.0.0/24 (no special-case)" do
      expect(described_class.call("127.0.0.1")).to eq("127.0.0.0/24")
    end

    it "edge: loopback IPv6 → ::/64" do
      expect(described_class.call("::1")).to eq("::/64")
    end

    it "edge: IPv4-mapped IPv6 unwraps to IPv4 prefix" do
      expect(described_class.call("::ffff:1.2.3.4")).to eq("1.2.3.0/24")
    end

    it "sad: invalid string → ArgumentError" do
      expect { described_class.call("not-an-ip") }.to raise_error(ArgumentError)
    end

    it "sad: nil → ArgumentError" do
      expect { described_class.call(nil) }.to raise_error(ArgumentError)
    end

    it "delegates to Pito::Auth::IpPrefix" do
      expect(Pito::Auth::IpPrefix).to receive(:call).with("1.1.1.1").and_call_original
      described_class.call("1.1.1.1")
    end
  end
end
