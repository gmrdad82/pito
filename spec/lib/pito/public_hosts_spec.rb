# frozen_string_literal: true

require "rails_helper"

# Pito::PublicHosts is the contract for the canonical public host derived from
# PITO_APP_BASE_URL. config/environments/production.rb mirrors this parsing
# inline (env files can't autoload app constants), so these specs guard the
# shape that production host/asset wiring depends on.
RSpec.describe Pito::PublicHosts do
  # Stub both readers the module uses: ENV["PITO_APP_BASE_URL"] (configured?)
  # and ENV.fetch("PITO_APP_BASE_URL", default) (app_base).
  def set_base(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PITO_APP_BASE_URL").and_return(value)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch)
      .with("PITO_APP_BASE_URL", described_class::DEFAULT_APP_BASE)
      .and_return(value || described_class::DEFAULT_APP_BASE)
  end

  context "when PITO_APP_BASE_URL is set (https tunnel/domain)" do
    before { set_base("https://app.pitomd.com") }

    it { expect(described_class.configured?).to be(true) }
    it { expect(described_class.app_base).to eq("https://app.pitomd.com") }
    it { expect(described_class.host).to eq("app.pitomd.com") }
    it { expect(described_class.scheme).to eq("https") }
  end

  context "with a trailing slash" do
    before { set_base("https://app.pitomd.com/") }

    it "is chomped from app_base" do
      expect(described_class.app_base).to eq("https://app.pitomd.com")
    end

    it "still parses the host" do
      expect(described_class.host).to eq("app.pitomd.com")
    end
  end

  context "when PITO_APP_BASE_URL is unset" do
    before { set_base(nil) }

    it "is not configured" do
      expect(described_class.configured?).to be(false)
    end

    it "falls back to the dev default base" do
      expect(described_class.app_base).to eq(described_class::DEFAULT_APP_BASE)
    end

    it "parses host + scheme of the default" do
      expect(described_class.host).to eq("localhost")
      expect(described_class.scheme).to eq("http")
    end
  end

  context "with an http LAN-style host" do
    before { set_base("http://192.168.0.10:3028") }

    it { expect(described_class.host).to eq("192.168.0.10") }
    it { expect(described_class.scheme).to eq("http") }
    it { expect(described_class.configured?).to be(true) }
  end
end
