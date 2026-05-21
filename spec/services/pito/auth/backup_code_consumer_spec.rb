require "rails_helper"

# Phase 25 — 01e. Pito::Auth::BackupCodeConsumer specs.
RSpec.describe Pito::Auth::BackupCodeConsumer do
  let(:user) { create(:user) }
  # Plaintext uses only the safe 28-char alphabet
  # (A-Z + 2-9, minus O I L B 8). 8 chars exact.
  let(:plaintext) { "ACDE2345" }
  let!(:row) do
    user.totp_backup_codes.create!(code_digest: BCrypt::Password.create(plaintext))
  end

  describe ".call (happy path)" do
    it "returns :ok for an unused matching code" do
      expect(described_class.call(user: user, code: plaintext)).to eq(:ok)
    end

    it "stamps used_at on the row" do
      described_class.call(user: user, code: plaintext)
      expect(row.reload.used_at).to be_present
    end

    it "strips whitespace before compare" do
      expect(described_class.call(user: user, code: "  #{plaintext}  ")).to eq(:ok)
    end
  end

  describe ".call (sad path)" do
    # P25 follow-up — F4. After tightening to `.unused`-only iteration,
    # a previously-stamped row is invisible to the consumer. The
    # plaintext therefore resolves to `:invalid`, not `:already_used`.
    # `:already_used` is still surfaced — but only via the parallel-
    # consume race inside the row-locked transaction.
    it "returns :invalid when the row was already consumed (used rows are skipped)" do
      row.update!(used_at: 1.minute.ago)
      expect(described_class.call(user: user, code: plaintext)).to eq(:invalid)
    end

    it "returns :invalid for a code that does not match any row" do
      expect(described_class.call(user: user, code: "ZZZZ9999")).to eq(:invalid)
    end

    it "returns :invalid on blank input" do
      expect(described_class.call(user: user, code: "")).to eq(:invalid)
      expect(described_class.call(user: user, code: nil)).to eq(:invalid)
    end

    it "raises on a nil user" do
      expect { described_class.call(user: nil, code: plaintext) }.to raise_error(ArgumentError)
    end
  end

  describe ".call (edge: reuse rejection)" do
    it "consume + consume returns :ok then :invalid (used row is skipped)" do
      expect(described_class.call(user: user, code: plaintext)).to eq(:ok)
      expect(described_class.call(user: user, code: plaintext)).to eq(:invalid)
    end
  end

  # P25 follow-up — F4. Length tightening: backup codes are always
  # exactly `BACKUP_CODE_LENGTH` chars. Anything shorter or longer must
  # short-circuit before the BCrypt compare.
  describe ".call (F4 — length tightening)" do
    it "rejects a 4-char code (previously accepted by the < 4 gate)" do
      expect(described_class.call(user: user, code: "ACDE")).to eq(:invalid)
    end

    it "rejects a 7-char code (off-by-one short)" do
      expect(described_class.call(user: user, code: "ACDE234")).to eq(:invalid)
    end

    it "rejects a 9-char code (off-by-one long)" do
      expect(described_class.call(user: user, code: "ACDE23456")).to eq(:invalid)
    end

    it "rejects a 16-char code (double-pasted)" do
      expect(described_class.call(user: user, code: plaintext * 2)).to eq(:invalid)
    end

    it "accepts an exactly-8-char valid alphabet code that matches a row" do
      expect(described_class.call(user: user, code: plaintext)).to eq(:ok)
    end
  end

  # P25 follow-up — F4. Alphabet validation: characters outside the
  # safe 28-char alphabet must short-circuit before any BCrypt compare.
  describe ".call (F4 — alphabet validation)" do
    it "rejects an 8-char code containing a '0' (forbidden glyph)" do
      expect(described_class.call(user: user, code: "ACDE2340")).to eq(:invalid)
    end

    it "rejects an 8-char code containing an 'O' (forbidden glyph)" do
      expect(described_class.call(user: user, code: "ACDEO345")).to eq(:invalid)
    end

    it "rejects an 8-char code containing an 'I' (forbidden glyph)" do
      expect(described_class.call(user: user, code: "ACDEI345")).to eq(:invalid)
    end

    it "rejects an 8-char code containing an 'L' (forbidden glyph)" do
      expect(described_class.call(user: user, code: "ACDEL345")).to eq(:invalid)
    end

    it "rejects an 8-char code containing a 'B' (forbidden glyph)" do
      expect(described_class.call(user: user, code: "ACDEB345")).to eq(:invalid)
    end

    it "rejects an 8-char code containing an '8' (forbidden glyph)" do
      expect(described_class.call(user: user, code: "ACDE8345")).to eq(:invalid)
    end

    it "rejects an 8-char code containing a '1' (forbidden glyph)" do
      expect(described_class.call(user: user, code: "ACDE1345")).to eq(:invalid)
    end

    it "rejects an 8-char code containing a punctuation char" do
      expect(described_class.call(user: user, code: "ACDE-345")).to eq(:invalid)
    end

    it "rejects an 8-char code containing a lowercase letter (alphabet is uppercase only)" do
      expect(described_class.call(user: user, code: "acde2345")).to eq(:invalid)
    end

    it "short-circuits before BCrypt when the alphabet check fails" do
      # If the alphabet gate works, no row's `matches?` should ever be
      # reached (so no BCrypt round-trips happen).
      expect_any_instance_of(TotpBackupCode).not_to receive(:matches?)
      described_class.call(user: user, code: "ACDE234@")
    end
  end

  # P25 follow-up — F4. Scope tightening: iteration is over `.unused`
  # rows only. This is verified by spying on the association proxy.
  describe ".call (F4 — .unused scope)" do
    it "scopes the iteration to .unused rows" do
      expect_any_instance_of(User).to receive(:totp_backup_codes)
        .and_wrap_original do |original|
          assoc = original.call
          expect(assoc).to receive(:unused).and_call_original
          assoc
        end
      described_class.call(user: user, code: plaintext)
    end

    it "does not BCrypt-compare against used rows" do
      # Stamp the only row as used. The consumer should not invoke
      # `matches?` on it at all.
      row.update!(used_at: 1.minute.ago)
      expect_any_instance_of(TotpBackupCode).not_to receive(:matches?)
      described_class.call(user: user, code: plaintext)
    end
  end
end
