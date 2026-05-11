require "rails_helper"

# Phase 8 — Tenant Drop + Email-Only Login (ADR 0003).
#
# User shape: email + password only. No `username`, no `tenant`,
# no `find_by_username_or_email`. Email is citext + unique
# install-wide; whitespace is stripped on assignment so user input
# round-trips through the form cleanly.
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

  describe "email validation" do
    it "is invalid with a nil email" do
      user = build(:user, email: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "is invalid with a blank email" do
      user = build(:user, email: "")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "is invalid with a whitespace-only email" do
      user = build(:user, email: "   ")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "is invalid with a malformed email (no @)" do
      user = build(:user, email: "not-an-email")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "is invalid with a malformed email (missing host)" do
      user = build(:user, email: "user@")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "rejects emails longer than 254 characters" do
      local = "a" * 250
      long  = "#{local}@x.test" # 250 + 7 = 257 chars
      user = build(:user, email: long)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "accepts a valid email" do
      user = build(:user, email: "alice@example.test")
      expect(user).to be_valid, "expected valid: #{user.errors.full_messages}"
    end

    it "strips surrounding whitespace on assignment" do
      user = create(:user, email: "  alice-#{SecureRandom.hex(3)}@example.test  ")
      expect(user.reload.email).to eq(user.email.strip)
      expect(user.email).not_to start_with(" ")
      expect(user.email).not_to end_with(" ")
    end

    it "is case-insensitive on email uniqueness via citext" do
      mixed = "USER-#{SecureRandom.hex(2)}@example.test"
      create(:user, email: mixed)
      dup = build(:user, email: mixed.downcase)
      expect(dup).not_to be_valid
      expect(dup.errors[:email]).to be_present
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
      user.email = "rotated-#{SecureRandom.hex(3)}@example.test"
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

  describe "no tenant / no username surface" do
    # Phase 8 archive checks. Asserts that the legacy plumbing is gone.
    it "does not declare a tenant association" do
      expect(User.reflect_on_association(:tenant)).to be_nil
    end

    it "does not respond to .find_by_username_or_email" do
      expect(User).not_to respond_to(:find_by_username_or_email)
    end

    it "does not have a username column" do
      expect(User.column_names).not_to include("username")
    end

    it "does not have a tenant_id column" do
      expect(User.column_names).not_to include("tenant_id")
    end
  end
end
