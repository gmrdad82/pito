# frozen_string_literal: true

require "rails_helper"

RSpec.describe Current do
  # Current inherits from ActiveSupport::CurrentAttributes, which provides
  # per-request/per-fiber attribute storage with automatic reset.

  FakeSession = Struct.new(:sid, :authenticated, :totp_verified_at, :created_at, :last_seen_at)

  after { Current.reset }

  describe "attribute :session" do
    it "is nil by default" do
      expect(Current.session).to be_nil
    end

    it "can be set and read within the same context" do
      fake_session = FakeSession.new("abc123", true)
      Current.session = fake_session
      expect(Current.session).to eq(fake_session)
    end

    it "is reset to nil after Current.reset" do
      Current.session = FakeSession.new("some-sid")
      Current.reset
      expect(Current.session).to be_nil
    end
  end

  describe "attribute :token" do
    it "is nil by default" do
      expect(Current.token).to be_nil
    end

    it "can be set and read" do
      Current.token = "Bearer eyJhbGci"
      expect(Current.token).to eq("Bearer eyJhbGci")
    end

    it "is reset to nil after Current.reset" do
      Current.token = "Bearer eyJhbGci"
      Current.reset
      expect(Current.token).to be_nil
    end
  end

  describe "auth-state contract" do
    it "fully authenticated: session present with authenticated flag" do
      # FakeSession positional: sid, authenticated
      Current.session = FakeSession.new("sid-xyz", true)
      expect(Current.session).not_to be_nil
      expect(Current.session.authenticated).to be(true)
    end

    it "anonymous: both session and token are nil" do
      expect(Current.session).to be_nil
      expect(Current.token).to be_nil
    end
  end
end
