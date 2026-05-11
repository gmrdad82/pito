require "rails_helper"

# Phase 25 — 01b (LD-5). New-location decision specs.
RSpec.describe Auth::NewLocationDetector do
  let(:user) { create(:user) }
  let(:fp)   { Digest::SHA256.hexdigest("nld-fp-1") }
  let(:ip)   { "10.10.0.0/24" }

  describe ".call" do
    context "happy: trusted pair" do
      before { create(:trusted_location, user: user, fingerprint_hash: fp, ip_prefix: ip) }

      it "returns :trusted" do
        expect(described_class.call(user: user, fingerprint_hash: fp, ip_prefix: ip)).to eq(:trusted)
      end
    end

    context "happy: untrusted, unblocked pair" do
      it "returns :new_location" do
        expect(described_class.call(user: user, fingerprint_hash: fp, ip_prefix: ip)).to eq(:new_location)
      end
    end

    context "sad: blocked pair takes precedence over trusted" do
      before do
        create(:trusted_location, user: user, fingerprint_hash: fp, ip_prefix: ip)
        create(:blocked_location, fingerprint_hash: fp, ip_prefix: ip, blocked_by_user: user)
      end

      it "returns :blocked_pair" do
        expect(described_class.call(user: user, fingerprint_hash: fp, ip_prefix: ip)).to eq(:blocked_pair)
      end
    end

    context "sad: blocked pair takes precedence over new_location" do
      before { create(:blocked_location, fingerprint_hash: fp, ip_prefix: ip, blocked_by_user: user) }

      it "returns :blocked_pair" do
        expect(described_class.call(user: user, fingerprint_hash: fp, ip_prefix: ip)).to eq(:blocked_pair)
      end
    end

    context "edge: user with zero trusted locations, first login" do
      it "is :new_location" do
        # No TrustedLocation rows, no BlockedLocation rows — first time
        # this user sees this (fingerprint, ip_prefix) pair.
        expect(described_class.call(user: user, fingerprint_hash: fp, ip_prefix: ip)).to eq(:new_location)
      end
    end

    context "edge: soft-unblocked pair is not :blocked_pair" do
      before do
        create(
          :blocked_location,
          :unblocked,
          fingerprint_hash: fp,
          ip_prefix: ip,
          blocked_by_user: user
        )
      end

      it "returns :new_location (unblocked block rows do not gate)" do
        expect(described_class.call(user: user, fingerprint_hash: fp, ip_prefix: ip)).to eq(:new_location)
      end
    end

    context "edge: nil / blank inputs" do
      it "is :new_location when user is nil" do
        expect(described_class.call(user: nil, fingerprint_hash: fp, ip_prefix: ip)).to eq(:new_location)
      end

      it "is :new_location when fingerprint is blank" do
        expect(described_class.call(user: user, fingerprint_hash: "", ip_prefix: ip)).to eq(:new_location)
      end

      it "is :new_location when ip_prefix is blank" do
        expect(described_class.call(user: user, fingerprint_hash: fp, ip_prefix: "")).to eq(:new_location)
      end
    end
  end
end
