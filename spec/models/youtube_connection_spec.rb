# frozen_string_literal: true

require "rails_helper"

RSpec.describe YoutubeConnection, type: :model do
  # ── Factories ────────────────────────────────────────────────────
  subject(:conn) { build(:youtube_connection) }

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:google_subject_id) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:access_token) }
    it { is_expected.to validate_presence_of(:expires_at) }
    it { is_expected.to validate_presence_of(:last_authorized_at) }

    it "requires uniqueness of google_subject_id" do
      create(:youtube_connection, google_subject_id: "dup_sub")
      dup = build(:youtube_connection, google_subject_id: "dup_sub")
      expect(dup).not_to be_valid
      expect(dup.errors[:google_subject_id]).to be_present
    end

    describe "scopes_must_be_array" do
      it "is valid when scopes is an Array" do
        conn.scopes = [ "https://www.googleapis.com/auth/youtube.readonly" ]
        expect(conn).to be_valid
      end

      it "is valid when scopes is an empty Array" do
        conn.scopes = []
        expect(conn).to be_valid
      end

      it "is invalid when scopes is a String" do
        conn.scopes = "youtube.readonly"
        expect(conn).not_to be_valid
        expect(conn.errors[:scopes]).to include("must be an Array")
      end

      it "is invalid when scopes is a Hash" do
        conn.scopes = { "read" => true }
        expect(conn).not_to be_valid
        expect(conn.errors[:scopes]).to include("must be an Array")
      end
    end
  end

  # ── Callbacks ────────────────────────────────────────────────────
  describe "before_validation :default_scopes_to_empty_array" do
    it "sets nil scopes to empty array before validation" do
      conn.scopes = nil
      conn.valid?
      expect(conn.scopes).to eq([])
    end

    it "does not overwrite an already-set scopes array" do
      conn.scopes = [ "https://www.googleapis.com/auth/youtube.readonly" ]
      conn.valid?
      expect(conn.scopes).to eq([ "https://www.googleapis.com/auth/youtube.readonly" ])
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────
  describe ".active" do
    it "returns connections where needs_reauth is false" do
      active  = create(:youtube_connection)
      _reauth = create(:youtube_connection, :needs_reauth)
      expect(YoutubeConnection.active).to include(active)
      expect(YoutubeConnection.active).not_to include(_reauth)
    end
  end

  # ── #access_token_expired? ────────────────────────────────────────
  describe "#access_token_expired?" do
    context "when expires_at is nil" do
      it "returns true" do
        conn.expires_at = nil
        expect(conn.access_token_expired?).to be(true)
      end
    end

    context "when expires_at is in the future (well beyond skew)" do
      it "returns false" do
        conn.expires_at = 10.minutes.from_now
        expect(conn.access_token_expired?).to be(false)
      end
    end

    context "when expires_at is in the past" do
      it "returns true" do
        conn.expires_at = 1.minute.ago
        expect(conn.access_token_expired?).to be(true)
      end
    end

    context "skew window" do
      it "returns true when expires_at is within the default 60-second skew" do
        conn.expires_at = 30.seconds.from_now
        expect(conn.access_token_expired?).to be(true)
      end

      it "returns false when expires_at is just beyond the custom skew" do
        conn.expires_at = 120.seconds.from_now
        expect(conn.access_token_expired?(skew: 60.seconds)).to be(false)
      end

      it "respects a custom skew value" do
        conn.expires_at = 10.seconds.from_now
        expect(conn.access_token_expired?(skew: 5.seconds)).to be(false)
        expect(conn.access_token_expired?(skew: 30.seconds)).to be(true)
      end
    end
  end

  # ── #has_scope? ──────────────────────────────────────────────────
  describe "#has_scope?" do
    before { conn.scopes = [ "https://www.googleapis.com/auth/youtube.readonly", "openid" ] }

    it "returns true when the scope is present" do
      expect(conn.has_scope?("openid")).to be(true)
    end

    it "returns false when the scope is absent" do
      expect(conn.has_scope?("profile")).to be(false)
    end

    it "coerces symbol argument to string" do
      expect(conn.has_scope?(:openid)).to be(true)
    end

    it "returns false when scopes is empty" do
      conn.scopes = []
      expect(conn.has_scope?("openid")).to be(false)
    end
  end

  # ── #scope_string ─────────────────────────────────────────────────
  describe "#scope_string" do
    it "returns space-joined scopes" do
      conn.scopes = [ "https://www.googleapis.com/auth/youtube", "openid" ]
      expect(conn.scope_string).to eq("https://www.googleapis.com/auth/youtube openid")
    end

    it "returns empty string when scopes is empty" do
      conn.scopes = []
      expect(conn.scope_string).to eq("")
    end
  end

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to have_many(:channels).with_foreign_key(:youtube_connection_id) }
  end

  # ── Token encryption ─────────────────────────────────────────────
  describe "token encryption" do
    it "encrypts access_token at rest" do
      record = create(:youtube_connection, access_token: "plaintext-access")
      raw = ActiveRecord::Base.connection.execute(
        "SELECT access_token FROM youtube_connections WHERE id = #{record.id}"
      ).first["access_token"]
      # The stored ciphertext must differ from the plaintext value
      expect(raw).not_to eq("plaintext-access")
    end

    it "round-trips access_token correctly" do
      record = create(:youtube_connection, access_token: "secret-token-value")
      expect(YoutubeConnection.find(record.id).access_token).to eq("secret-token-value")
    end

    it "round-trips refresh_token correctly" do
      record = create(:youtube_connection, refresh_token: "refresh-me-now")
      expect(YoutubeConnection.find(record.id).refresh_token).to eq("refresh-me-now")
    end
  end

  # ── #flag_needs_reauth! ──────────────────────────────────────────
  describe "#flag_needs_reauth!" do
    let(:connection) { create(:youtube_connection) }
    let!(:channel) { create(:channel, youtube_connection: connection, handle: "alpha") }

    it "flips needs_reauth to true" do
      connection.flag_needs_reauth!
      expect(connection.reload.needs_reauth).to be(true)
    end

    it "surfaces a reauth Notification, deduped while it stays unread" do
      expect { connection.flag_needs_reauth! }.to change(Notification, :count).by(1)
      expect { connection.flag_needs_reauth! }.not_to change(Notification, :count)
    end
  end
end
