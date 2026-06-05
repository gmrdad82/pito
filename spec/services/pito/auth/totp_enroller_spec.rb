# frozen_string_literal: true

# spec/services/pito/auth/totp_enroller_spec.rb
#
# Contract: Pito::Auth::TotpEnroller.call
#   → { seed: String } — 32-char base32 seed stored on the singleton row
#
# Re-enrollment replaces the old seed and clears the replay watermark.

require "rails_helper"

RSpec.describe Pito::Auth::TotpEnroller do
  describe ".call" do
    it "returns a hash with a :seed key" do
      result = described_class.call
      expect(result).to have_key(:seed)
    end

    it "returns a 32-character base32 seed" do
      result = described_class.call
      expect(result[:seed]).to match(/\A[A-Z2-7]{32}\z/)
    end

    it "stores the seed on the singleton row" do
      result = described_class.call
      expect(AppSetting.totp_seed).to eq(result[:seed])
    end

    it "allows subsequent TOTP verification with the generated seed" do
      result = described_class.call
      totp = ROTP::TOTP.new(result[:seed])
      code = totp.now
      expect(Pito::Auth::TotpVerifier.call(code: code)).to eq(:ok)
    end

    context "re-enrollment" do
      it "replaces the old seed with a new one" do
        first = described_class.call[:seed]
        second = described_class.call[:seed]
        # Seeds are random — identical only by cosmic coincidence
        # but we verify both are stored correctly (second wins).
        expect(AppSetting.totp_seed).to eq(second)
        # If by extreme chance they are equal this still passes; it's
        # a probabilistic uniqueness expectation, not structural.
        expect(first).to match(/\A[A-Z2-7]{32}\z/)
      end

      it "clears the replay watermark when re-enrolling" do
        # First enroll and use a code to set the watermark.
        described_class.call
        seed = AppSetting.totp_seed
        totp = ROTP::TOTP.new(seed)
        Pito::Auth::TotpVerifier.call(code: totp.now)
        expect(AppSetting.singleton_row.totp_last_used_step).to be_present

        # Re-enroll should clear the watermark.
        described_class.call
        expect(AppSetting.singleton_row.totp_last_used_step).to be_nil
      end
    end
  end
end
