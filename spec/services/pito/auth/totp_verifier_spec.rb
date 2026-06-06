# frozen_string_literal: true

# spec/services/pito/auth/totp_verifier_spec.rb
#
# Contract: Pito::Auth::TotpVerifier.call(code:)
#   → :ok    — valid 6-digit code matches the enrolled TOTP seed within the drift window
#   → :invalid — any other case (malformed, wrong, replay, no seed, etc.)
#
# Replay defense: once a step is accepted, the same step is rejected.
# Drift window: one step behind current is accepted (DRIFT_BEHIND_SECONDS = 30).

require "rails_helper"

RSpec.describe Pito::Auth::TotpVerifier do
  let(:seed) { ROTP::Base32.random_base32 }
  let(:totp) { ROTP::TOTP.new(seed) }

  before { AppSetting.enroll_totp!(seed: seed) }

  describe ".call" do
    context "valid 6-digit code" do
      it "returns :ok for the current step's code" do
        expect(described_class.call(code: totp.now)).to eq(:ok)
      end

      it "updates totp_last_used_step on success" do
        expect {
          described_class.call(code: totp.now)
        }.to change { AppSetting.singleton_row.totp_last_used_step }.from(nil)
      end
    end

    context "malformed / non-6-digit input" do
      it "returns :invalid for a 5-digit code" do
        expect(described_class.call(code: "12345")).to eq(:invalid)
      end

      it "returns :invalid for a 7-digit code" do
        expect(described_class.call(code: "1234567")).to eq(:invalid)
      end

      it "returns :invalid for non-numeric input" do
        expect(described_class.call(code: "abcdef")).to eq(:invalid)
      end

      it "returns :invalid for a code with whitespace (after strip/normalize)" do
        # Code with interior space — not a valid 6-digit string
        expect(described_class.call(code: "123 456")).to eq(:invalid)
      end

      it "returns :invalid for an empty string" do
        expect(described_class.call(code: "")).to eq(:invalid)
      end

      it "returns :invalid for nil (coerced to string)" do
        expect(described_class.call(code: nil)).to eq(:invalid)
      end

      it "returns :invalid for a code of all zeros (wrong value)" do
        expect(described_class.call(code: "000000")).to eq(:invalid)
      end
    end

    context "replay defense" do
      it "accepts the first use of a valid code" do
        code = totp.now
        expect(described_class.call(code: code)).to eq(:ok)
      end

      it "rejects the same code submitted a second time (replay)" do
        code = totp.now
        described_class.call(code: code) # first use — ok
        expect(described_class.call(code: code)).to eq(:invalid)
      end
    end

    context "drift window" do
      it "accepts a code from one step behind" do
        # Step behind = 30 seconds ago.
        one_step_ago = Time.current - Pito::Auth::TotpVerifier::STEP_SECONDS
        old_code = totp.at(one_step_ago)
        expect(described_class.call(code: old_code)).to eq(:ok)
      end

      it "rejects a replayed drift-window code on second submission" do
        one_step_ago = Time.current - Pito::Auth::TotpVerifier::STEP_SECONDS
        old_code = totp.at(one_step_ago)
        described_class.call(code: old_code) # first — ok
        expect(described_class.call(code: old_code)).to eq(:invalid)
      end
    end

    context "no seed enrolled" do
      before do
        # Remove the seed from the singleton row without triggering `enroll_totp!`
        AppSetting.singleton_row.update_columns(totp_seed_encrypted: nil, totp_last_used_step: nil)
      end

      it "returns :invalid when no seed is set" do
        expect(described_class.call(code: "123456")).to eq(:invalid)
      end
    end
  end
end
