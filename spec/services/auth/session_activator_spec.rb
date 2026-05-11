require "rails_helper"

# Phase 25 — 01b (LD-12). SessionActivator specs.
RSpec.describe Auth::SessionActivator do
  let(:user) { create(:user) }
  let(:fp)   { Digest::SHA256.hexdigest("act-fp-1") }
  let(:ip)   { "10.60.0.0/24" }

  def fake_request(remote_ip: "10.60.0.2", user_agent: "AgentActivator/1.0")
    request = ActionDispatch::TestRequest.create
    request.env["REMOTE_ADDR"] = remote_ip
    request.env["HTTP_USER_AGENT"] = user_agent
    request
  end

  before do
    Auth::GeoEnricher.reset_deferred!
    allow(Auth::GeoEnricher).to receive(:db_available?).and_return(false)
  end

  describe ".call (fresh session, trusted-location branch)" do
    it "creates a fresh :active session row" do
      record, _plaintext = described_class.call(
        user: user,
        request: fake_request,
        fingerprint_hash: fp,
        ip_prefix: ip,
        reason: :trusted_location_success
      )
      expect(record).to be_persisted
      expect(record.state_active?).to be true
    end

    it "writes a LoginAttempt row with reason: trusted_location_success" do
      expect {
        described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip,
          reason: :trusted_location_success
        )
      }.to change(LoginAttempt, :count).by(1)
      row = LoginAttempt.recent.first
      expect(row.result).to eq("success")
      expect(row.reason).to eq("trusted_location_success")
    end

    it "stamps the trusted_locations row (idempotent on the triple)" do
      expect {
        described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip,
          reason: :trusted_location_success
        )
      }.to change(TrustedLocation, :count).by(1)
      row = TrustedLocation.last
      expect(row.fingerprint_hash).to eq(fp)
      expect(row.ip_prefix).to eq(ip)
    end

    it "returns [record, plaintext] tuple for cookie minting" do
      record, plaintext = described_class.call(
        user: user,
        request: fake_request,
        fingerprint_hash: fp,
        ip_prefix: ip,
        reason: :trusted_location_success
      )
      expect(record).to be_persisted
      expect(plaintext).to be_a(String)
      expect(plaintext.length).to be > 16
    end
  end

  describe ".call (existing pending row → active transition)" do
    let!(:pending_row) { create(:session, :pending, user: user) }

    it "promotes the pending row to :active" do
      record, _ = described_class.call(
        user: user,
        request: fake_request,
        fingerprint_hash: fp,
        ip_prefix: ip,
        existing: pending_row
      )
      expect(record.id).to eq(pending_row.id)
      expect(record.reload.state_active?).to be true
    end

    it "rotates the token (digest changes after activation)" do
      original_digest = pending_row.token_digest
      _record, plaintext = described_class.call(
        user: user,
        request: fake_request,
        fingerprint_hash: fp,
        ip_prefix: ip,
        existing: pending_row
      )
      expect(plaintext).to be_present
      expect(pending_row.reload.token_digest).not_to eq(original_digest)
    end

    it "raises when the existing row is :expired" do
      expired = create(:session, :expired, user: user)
      expect {
        described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip,
          existing: expired
        )
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "raises when the existing row is :revoked" do
      revoked = create(:session, :revoked_state, user: user)
      expect {
        described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip,
          existing: revoked
        )
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe ".call (missing inputs)" do
    it "raises ArgumentError on missing user" do
      expect {
        described_class.call(user: nil, request: fake_request, fingerprint_hash: fp, ip_prefix: ip)
      }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError on blank fingerprint" do
      expect {
        described_class.call(user: user, request: fake_request, fingerprint_hash: "", ip_prefix: ip)
      }.to raise_error(ArgumentError)
    end
  end
end
