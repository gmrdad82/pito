require "rails_helper"

# Phase 25 — 01e. Auth::TotpVerifier specs.
RSpec.describe Auth::TotpVerifier do
  let(:seed) { "JBSWY3DPEHPK3PXP" }
  let(:user) { create(:user, totp_seed_encrypted: seed, totp_enabled_at: Time.current) }
  let(:totp) { ROTP::TOTP.new(seed) }

  describe ".call (happy path)" do
    it "returns :ok for the current-window code" do
      code = totp.now
      expect(described_class.call(user: user, code: code)).to eq(:ok)
    end

    it "returns :ok for a code from the previous 30-sec window (drift_behind)" do
      previous_code = nil
      Timecop.freeze(Time.now) do
        previous_code = totp.at(Time.now - 30)
      end
      code = previous_code
      expect(described_class.call(user: user, code: code)).to eq(:ok)
    rescue NameError
      # Fall back to manually computing the previous window code.
      previous = totp.at(Time.now - 30)
      expect(described_class.call(user: user, code: previous)).to eq(:ok)
    end
  end

  describe ".call (sad path)" do
    it "returns :invalid for a code 60 seconds old (outside drift window)" do
      old_code = totp.at(Time.now - 90)
      result = described_class.call(user: user, code: old_code)
      expect(result).to eq(:invalid)
    end

    it "returns :invalid for an incorrect code" do
      expect(described_class.call(user: user, code: "000000")).to eq(:invalid)
    end

    it "returns :invalid for a code that is not 6 digits" do
      expect(described_class.call(user: user, code: "12345")).to eq(:invalid)
      expect(described_class.call(user: user, code: "1234567")).to eq(:invalid)
      expect(described_class.call(user: user, code: "abcdef")).to eq(:invalid)
    end

    it "returns :invalid on empty / whitespace input" do
      expect(described_class.call(user: user, code: "")).to eq(:invalid)
      expect(described_class.call(user: user, code: "   ")).to eq(:invalid)
      expect(described_class.call(user: user, code: nil)).to eq(:invalid)
    end

    it "returns :invalid when the user is not enrolled" do
      bare_user = create(:user)
      expect(described_class.call(user: bare_user, code: "123456")).to eq(:invalid)
    end

    it "raises on a nil user" do
      expect { described_class.call(user: nil, code: "123456") }.to raise_error(ArgumentError)
    end
  end
end
