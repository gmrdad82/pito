require "rails_helper"

RSpec.describe Formatting::IpAddress do
  describe ".call" do
    context "with nil or blank" do
      it { expect(described_class.call(nil)).to eq("—") }
      it { expect(described_class.call("")).to eq("—") }
      it { expect(described_class.call(" ")).to eq("—") }
    end

    context "with IPv4" do
      it { expect(described_class.call("127.0.0.1")).to eq("127.0.0.1") }
      it { expect(described_class.call("192.168.1.42")).to eq("192.168.1.42") }
      it { expect(described_class.call("10.0.0.7")).to eq("10.0.0.7") }
    end

    context "with short IPv6 (<= 4 groups)" do
      it { expect(described_class.call("::1")).to eq("::1") }
      it { expect(described_class.call("fe80::1")).to eq("fe80::1") }
      it { expect(described_class.call("2001:db8:1:2")).to eq("2001:db8:1:2") }
    end

    context "with long IPv6 (> 4 groups)" do
      it "truncates 8-group IPv6" do
        ip = "2a0d:3344:5dfc:5808:dbdc:6327:dce9:24f1"
        expect(described_class.call(ip)).to eq("2a0d:3344:…:dce9:24f1")
      end

      it "truncates 5-group" do
        expect(described_class.call("a:b:c:d:e")).to eq("a:b:…:d:e")
      end
    end

    context "with IPAddr instances (Postgres inet column)" do
      it "handles IPv4 IPAddr" do
        expect(described_class.call(IPAddr.new("127.0.0.1"))).to eq("127.0.0.1")
      end

      it "handles short IPv6 IPAddr" do
        expect(described_class.call(IPAddr.new("::1"))).to eq("::1")
      end

      it "handles long IPv6 IPAddr by truncating" do
        ip = IPAddr.new("2a0d:3344:5dfc:5808:dbdc:6327:dce9:24f1")
        result = described_class.call(ip)
        expect(result).to match(/^2a0d:3344:…:.+:.+$/)
      end
    end
  end
end
