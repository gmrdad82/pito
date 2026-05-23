# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::IpAddress do
  describe ".call" do
    # IPv4 — always returned verbatim, well under any reasonable column
    # width.
    it "returns an IPv4 address unchanged" do
      expect(described_class.call("127.0.0.1")).to eq("127.0.0.1")
    end

    it "returns a private IPv4 address unchanged" do
      expect(described_class.call("192.168.1.42")).to eq("192.168.1.42")
    end

    # IPv6 8-group full form — middle-truncated to "<g1>:<g2>:…:<g7>:<g8>".
    it "middle-truncates a full 8-group IPv6 address" do
      expect(described_class.call("2a0d:3344:0db8:85a3:fe2b:250f:abcd:ef01"))
        .to eq("2a0d:3344:…:abcd:ef01")
    end

    it "middle-truncates an 8-group IPv6 address with leading-zero groups" do
      expect(described_class.call("2a0d:0000:0db8:85a3:fe2b:250f:abcd:ef01"))
        .to eq("2a0d:0000:…:abcd:ef01")
    end

    # IPv6 6 / 5 groups (long enough to need truncation).
    it "middle-truncates a 6-group IPv6 address" do
      expect(described_class.call("2a0d:3344:0db8:85a3:abcd:ef01"))
        .to eq("2a0d:3344:…:abcd:ef01")
    end

    it "middle-truncates an abbreviated 5-group IPv6 address" do
      expect(described_class.call("2a0d:3344::dce9:24f1"))
        .to eq("2a0d:3344:…:dce9:24f1")
    end

    # Short forms — ≤ 4 groups after `split(":")` stay as-is so we never
    # mangle a loopback / link-local / heavily-abbreviated address into
    # something less readable than its input.
    it "returns ::1 unchanged (3-group split)" do
      expect(described_class.call("::1")).to eq("::1")
    end

    it "returns an IPv6 address with 4 groups unchanged" do
      expect(described_class.call("2a0d:3344:abcd:ef01")).to eq("2a0d:3344:abcd:ef01")
    end

    # Empty / nil — em-dash sentinel, matching the rest of the formatter
    # family (used in any width-constrained TUI cell on /settings).
    it "returns the em-dash sentinel for nil" do
      expect(described_class.call(nil)).to eq("—")
    end

    it "returns the em-dash sentinel for an empty string" do
      expect(described_class.call("")).to eq("—")
    end

    it "returns the em-dash sentinel for a whitespace-only string" do
      expect(described_class.call("   ")).to eq("—")
    end

    # `Session#ip` is an `IPAddr` instance, not a string. The formatter
    # must accept any object that responds to `#to_s` (IPAddr does, with
    # `"2a0d:3344:…"`-style output).
    it "accepts an IPAddr instance and middle-truncates the rendered string" do
      ipaddr = IPAddr.new("2a0d:3344:5dfc:5808:5a1c:f8ff:fe2b:250f")
      expect(described_class.call(ipaddr)).to eq("2a0d:3344:…:fe2b:250f")
    end

    it "accepts an IPv4 IPAddr instance and returns it unchanged" do
      ipaddr = IPAddr.new("127.0.0.1")
      expect(described_class.call(ipaddr)).to eq("127.0.0.1")
    end
  end
end
