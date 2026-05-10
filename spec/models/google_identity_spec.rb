require "rails_helper"

# Phase 8 — tenant drop. `google_subject_id` uniqueness is install-wide
# (the upstream Google ID is globally unique on its own).
RSpec.describe GoogleIdentity, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it "does not declare a tenant association" do
      expect(GoogleIdentity.reflect_on_association(:tenant)).to be_nil
    end
    it "has many channels (via oauth_identity_id)" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)
      expect(identity.channels).to include(channel)
    end
  end

  describe "validations" do
    subject { build(:google_identity) }

    it { is_expected.to validate_presence_of(:google_subject_id) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:access_token) }
    it { is_expected.to validate_presence_of(:expires_at) }
    it { is_expected.to validate_presence_of(:last_authorized_at) }

    it "rejects scopes that are not Arrays" do
      identity = build(:google_identity, scopes: "openid email")
      expect(identity).not_to be_valid
      expect(identity.errors[:scopes]).to include("must be an Array")
    end

    it "permits an empty scopes array" do
      identity = build(:google_identity, scopes: [])
      expect(identity).to be_valid
    end

    it "enforces install-wide uniqueness of google_subject_id" do
      first = create(:google_identity)
      second = build(:google_identity, google_subject_id: first.google_subject_id)
      expect(second).not_to be_valid
      expect(second.errors[:google_subject_id]).to be_present
    end
  end

  describe "encryption at rest" do
    it "encrypts access_token (column read returns ciphertext, not plaintext)" do
      identity = create(:google_identity, access_token: "ya29.plaintext-secret-zzzz")
      raw = identity.read_attribute_before_type_cast(:access_token)
      expect(raw).not_to include("ya29.plaintext-secret-zzzz")
      expect(identity.reload.access_token).to eq("ya29.plaintext-secret-zzzz")
    end

    it "encrypts refresh_token" do
      identity = create(:google_identity, refresh_token: "1//plaintext-refresh-zzzz")
      raw = identity.read_attribute_before_type_cast(:refresh_token)
      expect(raw).not_to include("1//plaintext-refresh-zzzz")
      expect(identity.reload.refresh_token).to eq("1//plaintext-refresh-zzzz")
    end
  end

  describe "#access_token_expired?" do
    it "returns false when expires_at is far in the future" do
      identity = build(:google_identity, expires_at: 1.hour.from_now)
      expect(identity.access_token_expired?).to be(false)
    end

    it "returns true when expires_at is past" do
      identity = build(:google_identity, :expired)
      expect(identity.access_token_expired?).to be(true)
    end

    it "returns true when expires_at is within the default skew" do
      identity = build(:google_identity, expires_at: 30.seconds.from_now)
      expect(identity.access_token_expired?(skew: 60.seconds)).to be(true)
    end

    it "returns false when expires_at is just outside the skew" do
      identity = build(:google_identity, expires_at: 90.seconds.from_now)
      expect(identity.access_token_expired?(skew: 60.seconds)).to be(false)
    end
  end

  describe "#needs_reauth?" do
    it "returns the column value" do
      expect(build(:google_identity).needs_reauth?).to be(false)
      expect(build(:google_identity, :needs_reauth).needs_reauth?).to be(true)
    end
  end

  describe "#has_scope?" do
    it "checks membership in the scopes array" do
      identity = build(:google_identity)
      expect(identity.has_scope?("openid")).to be(true)
      expect(identity.has_scope?("https://www.googleapis.com/auth/youtube.readonly")).to be(true)
      expect(identity.has_scope?("https://www.googleapis.com/auth/youtube")).to be(false)
    end
  end

  describe "#scope_string" do
    it "joins scopes with single spaces" do
      identity = build(:google_identity, scopes: %w[openid email profile])
      expect(identity.scope_string).to eq("openid email profile")
    end
  end
end
