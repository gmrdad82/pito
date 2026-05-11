require "rails_helper"

RSpec.describe Pito::Auth::IpPrefix do
  describe ".call" do
    it "IPv4 → /24" do
      expect(described_class.call("8.8.4.4")).to eq("8.8.4.0/24")
    end

    it "IPv4 with prefix bits set" do
      expect(described_class.call("192.168.55.55")).to eq("192.168.55.0/24")
    end

    it "IPv6 → /64" do
      expect(described_class.call("2001:0db8:85a3:0000:0000:8a2e:0370:7334"))
        .to eq("2001:db8:85a3::/64")
    end

    it "accepts an IPAddr instance" do
      expect(described_class.call(IPAddr.new("4.3.2.1"))).to eq("4.3.2.0/24")
    end

    it "IPv4-mapped IPv6 unwraps to IPv4" do
      expect(described_class.call("::ffff:9.8.7.6")).to eq("9.8.7.0/24")
    end

    it "nil → ArgumentError" do
      expect { described_class.call(nil) }.to raise_error(ArgumentError, /required/)
    end

    it "garbage → ArgumentError" do
      expect { described_class.call("not-an-ip") }.to raise_error(ArgumentError, /invalid ip/)
    end
  end
end
