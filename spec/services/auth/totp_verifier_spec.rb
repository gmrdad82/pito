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

  # P25 follow-up — F9. Replay defense per RFC 6238 §5.2. The verifier
  # tracks the highest-numbered step a user has ever successfully
  # verified in `users.totp_last_used_step` and rejects any code that
  # resolves to a step `<=` that watermark.
  describe ".call (F9 — replay defense)" do
    it "accepts a code on first use and sets totp_last_used_step" do
      code = totp.now
      expect(described_class.call(user: user, code: code)).to eq(:ok)
      step_now = Time.now.to_i / Auth::TotpVerifier::STEP_SECONDS
      expect(user.reload.totp_last_used_step).to eq(step_now)
    end

    it "rejects the same code on second use within the 30-s window (replay)" do
      code = totp.now
      expect(described_class.call(user: user, code: code)).to eq(:ok)
      expect(described_class.call(user: user, code: code)).to eq(:invalid)
    end

    it "rejects a previous-window code after a current-window code has been accepted" do
      now_code = totp.now
      previous = totp.at(Time.now - 30)

      expect(described_class.call(user: user, code: now_code)).to eq(:ok)
      # Previous code resolves to a strictly smaller step than the one
      # we just stored — must be rejected.
      expect(described_class.call(user: user, code: previous)).to eq(:invalid)
    end

    it "advances the watermark when a code resolves to a higher step than the last one" do
      # Simulate the next 30-s window having elapsed by writing a
      # backdated watermark, then verify the current code advances it.
      current_step = Time.now.to_i / Auth::TotpVerifier::STEP_SECONDS
      user.update_columns(totp_last_used_step: current_step - 5)

      code = totp.now
      expect(described_class.call(user: user, code: code)).to eq(:ok)
      expect(user.reload.totp_last_used_step).to eq(current_step)
    end

    it "does NOT update totp_last_used_step on a rejected (wrong) code" do
      first_code = totp.now
      expect(described_class.call(user: user, code: first_code)).to eq(:ok)
      watermark = user.reload.totp_last_used_step

      expect(described_class.call(user: user, code: "000000")).to eq(:invalid)
      expect(user.reload.totp_last_used_step).to eq(watermark)
    end

    it "does NOT update totp_last_used_step on a rejected (replayed) code" do
      code = totp.now
      expect(described_class.call(user: user, code: code)).to eq(:ok)
      watermark = user.reload.totp_last_used_step

      expect(described_class.call(user: user, code: code)).to eq(:invalid)
      expect(user.reload.totp_last_used_step).to eq(watermark)
    end

    it "first verify on a fresh user (nil watermark) accepts and writes" do
      fresh = create(:user, totp_seed_encrypted: seed, totp_enabled_at: Time.current)
      expect(fresh.totp_last_used_step).to be_nil
      code = totp.now
      expect(described_class.call(user: fresh, code: code)).to eq(:ok)
      expect(fresh.reload.totp_last_used_step).not_to be_nil
    end
  end
end
