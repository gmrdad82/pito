require "rails_helper"

# Phase 25 — 01e. Auth::TotpEnroller specs.
RSpec.describe Auth::TotpEnroller do
  let(:user) { create(:user) }

  describe ".call (happy path)" do
    subject(:result) { described_class.call(user: user) }

    it "returns a 32-char base32 seed" do
      seed = result[:seed]
      expect(seed).to be_a(String)
      expect(seed.length).to eq(described_class::SEED_LENGTH)
      expect(seed).to match(/\A[A-Z2-7]+\z/)
    end

    it "returns exactly 10 plaintext backup codes" do
      expect(result[:codes].length).to eq(described_class::BACKUP_CODE_COUNT)
    end

    it "uses the safe 28-char alphabet for backup codes (no O / I / L / B / 0 / 1 / 8)" do
      forbidden = %w[O I L B 0 1 8]
      result[:codes].each do |code|
        forbidden.each do |char|
          expect(code).not_to include(char), "code #{code} contains forbidden char #{char}"
        end
      end
    end

    it "persists the encrypted seed on the user row" do
      seed = result[:seed]
      expect(user.reload.totp_seed_encrypted).to eq(seed)
    end

    it "persists 10 backup code rows with bcrypt digests" do
      result
      expect(user.totp_backup_codes.count).to eq(10)
      user.totp_backup_codes.each do |row|
        expect(row.code_digest).to start_with("$2a$").or start_with("$2b$").or start_with("$2y$")
      end
    end

    it "every returned plaintext code matches its stored bcrypt digest" do
      result[:codes].each do |plaintext|
        row = user.totp_backup_codes.detect { |r| r.matches?(plaintext) }
        expect(row).not_to be_nil, "no digest row matched plaintext #{plaintext}"
      end
    end

    it "does NOT stamp totp_enabled_at (confirm step does)" do
      result
      expect(user.reload.totp_enabled_at).to be_nil
    end
  end

  describe ".call (re-enrollment after disable)" do
    it "replaces seed + codes when user is not currently enrolled" do
      user.update!(
        totp_seed_encrypted: nil,
        totp_disabled_at: 1.day.ago
      )
      user.totp_backup_codes.create!(code_digest: BCrypt::Password.create("STALE234"))

      result = described_class.call(user: user)

      expect(user.reload.totp_seed_encrypted).to eq(result[:seed])
      # Stale code wiped; 10 fresh codes.
      expect(user.totp_backup_codes.count).to eq(10)
    end

    it "clears the totp_disabled_at stamp" do
      user.update!(totp_disabled_at: 1.day.ago)
      described_class.call(user: user)
      expect(user.reload.totp_disabled_at).to be_nil
    end
  end

  describe ".call (sad path)" do
    it "raises AlreadyEnrolled when the user is already enrolled" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: Time.current)
      expect {
        described_class.call(user: user)
      }.to raise_error(described_class::AlreadyEnrolled)
    end

    it "raises ArgumentError when user is nil" do
      expect { described_class.call(user: nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".call (flaw class)" do
    it "the returned seed decrypts back to the same plaintext stored at rest" do
      result = described_class.call(user: user)
      expect(user.reload.totp_seed_encrypted).to eq(result[:seed])
    end

    it "every backup code is exactly BACKUP_CODE_LENGTH chars" do
      result = described_class.call(user: user)
      result[:codes].each do |code|
        expect(code.length).to eq(described_class::BACKUP_CODE_LENGTH)
      end
    end
  end

  # P25 follow-up — F10. Backup codes are minted from an explicit
  # CSPRNG (`SecureRandom.random_number`) rather than `Array#sample`.
  describe ".generate_code (F10 — CSPRNG generation)" do
    it "produces a string of exactly BACKUP_CODE_LENGTH chars" do
      100.times do
        code = described_class.generate_code
        expect(code.length).to eq(described_class::BACKUP_CODE_LENGTH)
      end
    end

    it "every character is drawn from BACKUP_CODE_ALPHABET" do
      100.times do
        code = described_class.generate_code
        code.each_char do |c|
          expect(described_class::BACKUP_CODE_ALPHABET).to include(c),
            "character #{c.inspect} in #{code} is not in the safe alphabet"
        end
      end
    end

    it "invokes SecureRandom.random_number (the explicit CSPRNG path)" do
      # Spy on the CSPRNG. Each character is drawn by one call to
      # `SecureRandom.random_number(BACKUP_CODE_ALPHABET.length)`, so
      # one `generate_code` invocation must produce exactly
      # `BACKUP_CODE_LENGTH` calls with that specific argument. Use
      # `.with(...)` to filter out unrelated SecureRandom traffic
      # (e.g., the BCrypt cost path or the test framework's own
      # random plumbing) and `.exactly(...)` against that filtered
      # count.
      allow(SecureRandom).to receive(:random_number).and_call_original
      described_class.generate_code
      expect(SecureRandom).to have_received(:random_number)
        .with(described_class::BACKUP_CODE_ALPHABET.length)
        .exactly(described_class::BACKUP_CODE_LENGTH).times
    end

    it "produces a roughly uniform character distribution over 1000 samples" do
      # Distribution sanity check — 1000 codes of length 8 = 8000 draws
      # over a 28-symbol alphabet. Expected frequency per symbol is
      # 8000 / 28 ≈ 285. The tolerance is intentionally loose (±60%
      # of expected) so this assertion does not flake on the test runner
      # — the goal is to catch a wildly skewed RNG (e.g. all-zero, or
      # always-the-same-char), not to chi-square the CSPRNG.
      counts = Hash.new(0)
      1000.times do
        described_class.generate_code.each_char { |c| counts[c] += 1 }
      end

      expected = (1000 * described_class::BACKUP_CODE_LENGTH) /
                 described_class::BACKUP_CODE_ALPHABET.length.to_f
      lower = expected * 0.4
      upper = expected * 1.6

      described_class::BACKUP_CODE_ALPHABET.each do |c|
        actual = counts[c]
        expect(actual).to be_between(lower, upper),
          "char #{c.inspect} appeared #{actual} times, expected ~#{expected.round} (range #{lower.round}..#{upper.round})"
      end
    end

    it "two generated codes are not equal (collision sanity)" do
      a = described_class.generate_code
      b = described_class.generate_code
      expect(a).not_to eq(b)
    end
  end
end
