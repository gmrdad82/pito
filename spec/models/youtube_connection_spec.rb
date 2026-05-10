require "rails_helper"

# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). `google_subject_id` uniqueness is install-wide
# (the upstream Google ID is globally unique on its own — Phase 8
# dropped the tenant-scoped composite).
RSpec.describe YoutubeConnection, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }

    it "has many channels via youtube_connection_id" do
      connection = create(:youtube_connection)
      a = create(:channel, youtube_connection: connection)
      b = create(:channel, youtube_connection: connection)
      expect(connection.channels).to contain_exactly(a, b)
    end

    it "has many videos via youtube_connection_id" do
      connection = create(:youtube_connection)
      v1 = create(:video, youtube_connection: connection)
      v2 = create(:video, youtube_connection: connection)
      expect(connection.videos).to contain_exactly(v1, v2)
    end

    it "has many youtube_api_calls via youtube_connection_id" do
      connection = create(:youtube_connection)
      r1 = create(:youtube_api_call, youtube_connection: connection)
      r2 = create(:youtube_api_call, youtube_connection: connection)
      expect(connection.youtube_api_calls).to contain_exactly(r1, r2)
    end

    it "destroying the connection nullifies its channels (preserves Phase 7C disconnect-lifecycle)" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      connection.destroy!

      expect(Channel.unscoped.where(id: channel.id).exists?).to be(true)
      expect(channel.reload.youtube_connection_id).to be_nil
    end

    it "destroying the user destroys all of the user's youtube_connections (and nullifies the user's channels)" do
      user = create(:user)
      connection = create(:youtube_connection, user: user)
      channel = create(:channel, youtube_connection: connection)

      user.destroy

      expect(YoutubeConnection.unscoped.where(user_id: user.id)).to be_empty
      expect(Channel.unscoped.where(id: channel.id).exists?).to be(true)
      expect(channel.reload.youtube_connection_id).to be_nil
    end
  end

  describe "validations" do
    subject { build(:youtube_connection) }

    it { is_expected.to validate_presence_of(:google_subject_id) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:access_token) }
    it { is_expected.to validate_presence_of(:expires_at) }
    it { is_expected.to validate_presence_of(:last_authorized_at) }

    it "rejects scopes that are not Arrays" do
      connection = build(:youtube_connection, scopes: "openid email")
      expect(connection).not_to be_valid
      expect(connection.errors[:scopes]).to include("must be an Array")
    end

    it "permits an empty scopes array" do
      connection = build(:youtube_connection, scopes: [])
      expect(connection).to be_valid
    end

    it "enforces install-wide uniqueness of google_subject_id" do
      first = create(:youtube_connection)
      second = build(:youtube_connection, google_subject_id: first.google_subject_id)
      expect(second).not_to be_valid
      expect(second.errors[:google_subject_id]).to be_present
    end
  end

  describe "encryption at rest" do
    it "encrypts access_token (column read returns ciphertext, not plaintext)" do
      connection = create(:youtube_connection, access_token: "ya29.plaintext-secret-zzzz")
      raw = connection.read_attribute_before_type_cast(:access_token)
      expect(raw).not_to include("ya29.plaintext-secret-zzzz")
      expect(connection.reload.access_token).to eq("ya29.plaintext-secret-zzzz")
    end

    it "encrypts refresh_token" do
      connection = create(:youtube_connection, refresh_token: "1//plaintext-refresh-zzzz")
      raw = connection.read_attribute_before_type_cast(:refresh_token)
      expect(raw).not_to include("1//plaintext-refresh-zzzz")
      expect(connection.reload.refresh_token).to eq("1//plaintext-refresh-zzzz")
    end
  end

  describe "#access_token_expired?" do
    it "returns false when expires_at is far in the future" do
      connection = build(:youtube_connection, expires_at: 1.hour.from_now)
      expect(connection.access_token_expired?).to be(false)
    end

    it "returns true when expires_at is past" do
      connection = build(:youtube_connection, :expired)
      expect(connection.access_token_expired?).to be(true)
    end

    it "returns true when expires_at is within the default skew" do
      connection = build(:youtube_connection, expires_at: 30.seconds.from_now)
      expect(connection.access_token_expired?(skew: 60.seconds)).to be(true)
    end

    it "returns false when expires_at is just outside the skew" do
      connection = build(:youtube_connection, expires_at: 90.seconds.from_now)
      expect(connection.access_token_expired?(skew: 60.seconds)).to be(false)
    end
  end

  describe "#needs_reauth?" do
    it "returns the column value" do
      expect(build(:youtube_connection).needs_reauth?).to be(false)
      expect(build(:youtube_connection, :needs_reauth).needs_reauth?).to be(true)
    end
  end

  describe "#has_scope?" do
    it "checks membership in the scopes array" do
      connection = build(:youtube_connection)
      expect(connection.has_scope?("openid")).to be(true)
      expect(connection.has_scope?("https://www.googleapis.com/auth/youtube.readonly")).to be(true)
      expect(connection.has_scope?("https://www.googleapis.com/auth/youtube")).to be(false)
    end
  end

  describe "#scope_string" do
    it "joins scopes with single spaces" do
      connection = build(:youtube_connection, scopes: %w[openid email profile])
      expect(connection.scope_string).to eq("openid email profile")
    end
  end
end
