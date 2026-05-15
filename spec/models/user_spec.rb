require "rails_helper"

# Phase 29 — Unit A2. User auth refactor: username login.
#
# User shape: username + password only. No `email`, no `tenant`.
# `username` is citext + unique install-wide; whitespace is stripped
# and the value downcased before validation so user input round-trips
# through the form cleanly. Format: alphanumerics + underscore with
# single internal dot / hyphen separators, 3..32 chars.
RSpec.describe User, type: :model do
  subject { build(:user) }

  describe "associations" do
    it { is_expected.to have_many(:sessions).dependent(:destroy) }

    # Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
    it { is_expected.to have_many(:youtube_connections).dependent(:destroy) }

    it "destroying a user cascades to their youtube_connections" do
      user = create(:user)
      connection = create(:youtube_connection, user: user)

      user.destroy

      expect(YoutubeConnection.unscoped.where(id: connection.id).exists?).to be(false)
    end
  end

  describe "username validation" do
    it "is invalid with a nil username" do
      user = build(:user, username: nil)
      expect(user).not_to be_valid
      expect(user.errors[:username]).to be_present
    end

    it "is invalid with a blank username" do
      user = build(:user, username: "")
      expect(user).not_to be_valid
      expect(user.errors[:username]).to be_present
    end

    it "is invalid with a whitespace-only username" do
      user = build(:user, username: "   ")
      expect(user).not_to be_valid
      expect(user.errors[:username]).to be_present
    end

    describe "length" do
      it "rejects a 2-character username" do
        user = build(:user, username: "ab")
        expect(user).not_to be_valid
        expect(user.errors[:username]).to be_present
      end

      it "accepts a 3-character username" do
        user = build(:user, username: "abc")
        expect(user).to be_valid, "expected valid: #{user.errors.full_messages}"
      end

      it "accepts a 32-character username" do
        user = build(:user, username: "a" * 32)
        expect(user).to be_valid, "expected valid: #{user.errors.full_messages}"
      end

      it "rejects a 33-character username" do
        user = build(:user, username: "a" * 33)
        expect(user).not_to be_valid
        expect(user.errors[:username]).to be_present
      end
    end

    describe "format" do
      %w[abc a_b a.b a-b user_1 owner].each do |valid|
        it "accepts #{valid.inspect}" do
          user = build(:user, username: valid)
          expect(user).to be_valid, "expected #{valid.inspect} valid: #{user.errors.full_messages}"
        end
      end

      [
        ".abc", "abc.", "-abc", "abc-", "a..b", "a--b", "a.-b",
        "has space", "user@host", "user!", "a/b"
      ].each do |invalid|
        it "rejects #{invalid.inspect}" do
          user = build(:user, username: invalid)
          expect(user).not_to be_valid
          expect(user.errors[:username]).to be_present
        end
      end
    end

    it "downcases the username before validation (stored canonical)" do
      user = create(:user, username: "MixedCase_#{SecureRandom.hex(2)}")
      expect(user.reload.username).to eq(user.username.downcase)
      expect(user.username).to eq(user.username.downcase)
    end

    it "strips surrounding whitespace before validation" do
      raw = "  owner_#{SecureRandom.hex(2)}  "
      user = create(:user, username: raw)
      expect(user.reload.username).to eq(raw.strip.downcase)
      expect(user.username).not_to start_with(" ")
      expect(user.username).not_to end_with(" ")
    end

    it "is case-insensitive on uniqueness via citext" do
      mixed = "Owner#{SecureRandom.hex(2)}"
      create(:user, username: mixed)
      dup = build(:user, username: mixed.downcase)
      expect(dup).not_to be_valid
      expect(dup.errors[:username]).to be_present
    end
  end

  describe "no email surface (Phase 29 — Unit A2)" do
    it "does not have an email column" do
      expect(User.column_names).not_to include("email")
    end

    it "does not declare EMAIL_MAX_LENGTH" do
      expect(User.const_defined?(:EMAIL_MAX_LENGTH)).to be(false)
    end

    it "saves a User that was never assigned an email" do
      user = build(:user)
      expect(user).to be_valid
      expect { user.save! }.not_to raise_error
    end
  end

  describe "has_secure_password" do
    it "round-trips a valid password" do
      user = create(:user, password: "supersecret", password_confirmation: "supersecret")
      expect(user.password_digest).to be_present
      expect(user.authenticate("supersecret")).to eq(user)
      expect(user.authenticate("wrong")).to be(false)
    end

    it "rejects empty passwords on authenticate" do
      user = create(:user, password: "supersecret", password_confirmation: "supersecret")
      expect(user.authenticate("")).to be(false)
    end

    # The model gates on a minimum password length only when a fresh
    # password is supplied (the `password` accessor is transient —
    # present at create / change time, blank otherwise).
    it "rejects passwords shorter than 8 characters" do
      user = build(:user, password: "short", password_confirmation: "short")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "accepts passwords of exactly 8 characters" do
      user = build(:user, password: "exactly8", password_confirmation: "exactly8")
      expect(user).to be_valid, "expected user with 8-char password to be valid: #{user.errors.full_messages}"
    end

    it "does not re-validate password length on a row whose password is untouched" do
      user = create(:user, password: "long-enough", password_confirmation: "long-enough")
      user.username = "rotated_#{SecureRandom.hex(3)}"
      expect(user).to be_valid
    end
  end

  describe "time_zone column (Phase 26 — 01a)" do
    it "defaults to Etc/UTC for a fresh row (DB default)" do
      user = create(:user)
      expect(user.reload.time_zone).to eq("Etc/UTC")
    end

    it "round-trips a stored zone through save + reload" do
      user = create(:user, time_zone: "Europe/Bucharest")
      expect(user.reload.time_zone).to eq("Europe/Bucharest")
    end

    it "is NOT NULL at the column level (defensive backstop on validation)" do
      column = User.columns_hash["time_zone"]
      expect(column).to be_present
      expect(column.null).to be(false)
      expect(column.default).to eq("Etc/UTC")
    end

    it "rejects an invalid zone via the Timezoned concern" do
      user = build(:user, time_zone: "Not/A/Zone")
      expect(user).not_to be_valid
      expect(user.errors[:time_zone]).to be_present
    end

    it "exposes #tz returning the resolved ActiveSupport::TimeZone" do
      user = create(:user, time_zone: "America/Los_Angeles")
      expect(user.tz.tzinfo.name).to eq("America/Los_Angeles")
    end
  end

  describe "preferred_games_display_mode enum (Phase 27 — 01d)" do
    # Happy path — the enum maps to the locked integer values and
    # exposes the prefixed predicate / bang helpers.
    it "defaults to grid for a fresh row" do
      user = create(:user)
      expect(user.reload.preferred_games_display_mode).to eq("grid")
    end

    it "exposes the three enum keys" do
      expect(User.preferred_games_display_modes.keys)
        .to contain_exactly("grid", "list", "shelves_by_letter")
    end

    # Flaw guard — integer values are load-bearing for production
    # data. Asserting the mapping explicitly so an accidental
    # reorder is caught at test time.
    it "maps enum keys to the stable integers 0/1/2" do
      expect(User.preferred_games_display_modes).to eq(
        "grid" => 0,
        "list" => 1,
        "shelves_by_letter" => 2
      )
    end

    it "exposes prefixed predicate methods" do
      user = create(:user, preferred_games_display_mode: :list)
      expect(user).to be_games_display_list
      expect(user).not_to be_games_display_grid
      expect(user).not_to be_games_display_shelves_by_letter
    end

    it "exposes prefixed bang methods" do
      user = create(:user)
      expect { user.games_display_shelves_by_letter! }
        .to change { user.reload.preferred_games_display_mode }
        .from("grid").to("shelves_by_letter")
    end

    # Sad — assigning an unknown value raises.
    it "raises ArgumentError on an invalid value" do
      user = build(:user)
      expect { user.preferred_games_display_mode = :tilemap }
        .to raise_error(ArgumentError)
    end

    # Edge — pre-existing rows get `grid` via the column default.
    it "is NOT NULL at the column level with default 0 (grid)" do
      column = User.columns_hash["preferred_games_display_mode"]
      expect(column).to be_present
      expect(column.null).to be(false)
      expect(column.default.to_i).to eq(0)
    end
  end

  # Phase 25 — 01b. Trusted-location + pending-session helpers.
  describe "#trusted_location?" do
    let(:user) { create(:user) }
    let(:fp) { Digest::SHA256.hexdigest("user-trust-1") }
    let(:ip_prefix) { "10.40.0.0/24" }

    it "returns true iff a trusted_locations row exists for the triple" do
      create(:trusted_location, user: user, fingerprint_hash: fp, ip_prefix: ip_prefix)
      expect(user.trusted_location?(fingerprint: fp, ip_prefix: ip_prefix)).to be true
    end

    it "returns false when no trusted row matches" do
      expect(user.trusted_location?(fingerprint: fp, ip_prefix: ip_prefix)).to be false
    end

    it "returns false when only another user has the row" do
      other = create(:user)
      create(:trusted_location, user: other, fingerprint_hash: fp, ip_prefix: ip_prefix)
      expect(user.trusted_location?(fingerprint: fp, ip_prefix: ip_prefix)).to be false
    end
  end

  describe "#has_pending_session?" do
    let(:user) { create(:user) }

    it "is true when at least one pending in-window session exists" do
      create(:session, :pending, user: user)
      expect(user.has_pending_session?).to be true
    end

    it "is false when only expired-pending sessions exist" do
      create(:session, :expired_pending, user: user)
      expect(user.has_pending_session?).to be false
    end

    it "is false when only active sessions exist" do
      create(:session, user: user)
      expect(user.has_pending_session?).to be false
    end
  end

  describe "TOTP 2FA (Phase 25 — 01e)" do
    let(:user) { create(:user) }

    describe "#totp_enabled?" do
      it "is false when no seed is set" do
        expect(user.totp_enabled?).to be false
      end

      it "is true when a seed is set and disabled_at is nil" do
        user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: Time.current)
        expect(user.totp_enabled?).to be true
      end

      it "is false when disabled_at is stamped even with a seed (defensive)" do
        user.update!(
          totp_seed_encrypted: "JBSWY3DPEHPK3PXP",
          totp_enabled_at: 1.hour.ago,
          totp_disabled_at: Time.current
        )
        expect(user.totp_enabled?).to be false
      end
    end

    describe "#totp_configured?" do
      it "is false for a fresh user with no seed" do
        expect(user.totp_configured?).to be false
      end

      it "is true with a seed and enabled_at present and disabled_at nil" do
        user.update!(
          totp_seed_encrypted: "JBSWY3DPEHPK3PXP",
          totp_enabled_at: Time.current,
          totp_disabled_at: nil
        )
        expect(user.totp_configured?).to be true
      end

      it "is false when disabled_at is stamped even with a seed" do
        user.update!(
          totp_seed_encrypted: "JBSWY3DPEHPK3PXP",
          totp_enabled_at: 1.hour.ago,
          totp_disabled_at: Time.current
        )
        expect(user.totp_configured?).to be false
      end

      it "tracks #totp_enabled? exactly" do
        expect(user.totp_configured?).to eq(user.totp_enabled?)
        user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: Time.current)
        expect(user.totp_configured?).to eq(user.totp_enabled?)
      end
    end

    describe "#totp_uri" do
      it "returns nil when no seed is set" do
        expect(user.totp_uri(issuer: "pito")).to be_nil
      end

      it "returns a valid otpauth:// URI when a seed is set" do
        user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP")
        uri = user.totp_uri(issuer: "pito")
        expect(uri).to start_with("otpauth://totp/")
        expect(uri).to include("issuer=pito")
        expect(uri).to include("secret=JBSWY3DPEHPK3PXP")
      end

      it "uses the username as the account label in the provisioning URI" do
        user.update!(username: "label_user_#{SecureRandom.hex(2)}", totp_seed_encrypted: "JBSWY3DPEHPK3PXP")
        uri = user.totp_uri(issuer: "pito")
        expect(uri).to include(CGI.escape(user.username))
      end
    end

    describe "encryption at rest" do
      it "stores the totp_seed_encrypted column as ciphertext, not plaintext" do
        user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP")
        raw = User.connection.select_value(
          "SELECT totp_seed_encrypted FROM users WHERE id = #{user.id}"
        ).to_s
        expect(raw).not_to be_empty
        expect(raw).not_to include("JBSWY3DPEHPK3PXP")
      end

      it "round-trips the plaintext through the model" do
        user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP")
        expect(user.reload.totp_seed_encrypted).to eq("JBSWY3DPEHPK3PXP")
      end
    end

    describe "has_many :totp_backup_codes" do
      it "cascades destroy" do
        user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP")
        user.totp_backup_codes.create!(code_digest: BCrypt::Password.create("abc"))
        expect { user.destroy }.to change(TotpBackupCode, :count).by(-1)
      end
    end

    # P25 follow-up — F9. Replay-defense column.
    describe "totp_last_used_step column" do
      it "is present as a bigint" do
        column = User.columns_hash["totp_last_used_step"]
        expect(column).to be_present
        expect(column.sql_type).to eq("bigint")
      end

      it "is nullable (fresh users have no watermark)" do
        column = User.columns_hash["totp_last_used_step"]
        expect(column.null).to be(true)
      end

      it "defaults to nil for a fresh user" do
        fresh = create(:user)
        expect(fresh.reload.totp_last_used_step).to be_nil
      end

      it "round-trips a stored integer step" do
        user.update!(totp_last_used_step: 59_284_000)
        expect(user.reload.totp_last_used_step).to eq(59_284_000)
      end
    end
  end

  describe "no tenant surface" do
    # Phase 8 archive checks. Asserts that the legacy plumbing is gone.
    it "does not declare a tenant association" do
      expect(User.reflect_on_association(:tenant)).to be_nil
    end

    it "does not respond to .find_by_username_or_email" do
      expect(User).not_to respond_to(:find_by_username_or_email)
    end

    it "has a username column (Phase 29 — Unit A2)" do
      expect(User.column_names).to include("username")
    end

    it "does not have a tenant_id column" do
      expect(User.column_names).not_to include("tenant_id")
    end
  end
end
