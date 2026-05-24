# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::IpAddress do
  describe ".call" do
    # IPv4 — short addresses returned verbatim, addresses over MAX_LEN
    # (13) get the same trailing-ellipsis treatment as IPv6.
    it "returns a short IPv4 address unchanged" do
      expect(described_class.call("127.0.0.1")).to eq("127.0.0.1")
    end

    it "returns a 13-char IPv4 address unchanged" do
      expect(described_class.call("192.168.1.100")).to eq("192.168.1.100")
    end

    it "trims a 15-char IPv4 address with trailing ellipsis" do
      expect(described_class.call("255.255.255.255")).to eq("255.255.255.…")
    end

    # IPv6 — trailing ellipsis after the longest group-boundary head that
    # fits within MAX_LEN - 1 chars (12 for the head + 1 for the ellipsis).
    it "trims a full 8-group IPv6 with trailing ellipsis at a group boundary" do
      expect(described_class.call("2a0d:3344:0db8:85a3:fe2b:250f:abcd:ef01"))
        .to eq("2a0d:3344…")
    end

    it "trims a 7-group IPv6 with trailing ellipsis" do
      expect(described_class.call("2a0d:3344:7a3e:9efe:0c1f:dce9:24f1"))
        .to eq("2a0d:3344…")
    end

    it "trims a 5-group abbreviated IPv6 with trailing ellipsis" do
      # The empty group from `::` joins with a colon, producing a
      # trailing colon before the ellipsis. Acceptable cosmetic edge.
      expect(described_class.call("2a0d:3344::dce9:24f1")).to eq("2a0d:3344:…")
    end

    # Short IPv6 — fits within MAX_LEN, returned unchanged.
    it "returns ::1 unchanged" do
      expect(described_class.call("::1")).to eq("::1")
    end

    it "returns a 13-char or shorter IPv6 unchanged" do
      expect(described_class.call("2a0d:abcd:ef")).to eq("2a0d:abcd:ef")
    end

    # Empty / nil — em-dash sentinel.
    it "returns the em-dash sentinel for nil" do
      expect(described_class.call(nil)).to eq("—")
    end

    it "returns the em-dash sentinel for an empty string" do
      expect(described_class.call("")).to eq("—")
    end

    it "returns the em-dash sentinel for a whitespace-only string" do
      expect(described_class.call("   ")).to eq("—")
    end

    # `Session#ip` is an `IPAddr` instance — formatter must accept any
    # object responding to `#to_s`.
    it "accepts an IPAddr instance and trims with trailing ellipsis" do
      ipaddr = IPAddr.new("2a0d:3344:5dfc:5808:5a1c:f8ff:fe2b:250f")
      expect(described_class.call(ipaddr)).to eq("2a0d:3344…")
    end

    it "accepts an IPv4 IPAddr instance and returns it unchanged" do
      ipaddr = IPAddr.new("127.0.0.1")
      expect(described_class.call(ipaddr)).to eq("127.0.0.1")
    end
  end
end
