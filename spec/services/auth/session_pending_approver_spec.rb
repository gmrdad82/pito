require "rails_helper"

# Phase 25 — 01b. SessionPendingApprover specs.
RSpec.describe Auth::SessionPendingApprover do
  let(:user) { create(:user) }
  let(:fp)   { Digest::SHA256.hexdigest("spa-fp-1") }
  let(:ip)   { "10.50.0.0/24" }

  def fake_request(remote_ip: "10.50.0.2", user_agent: "AgentPending/1.0")
    request = ActionDispatch::TestRequest.create
    request.env["REMOTE_ADDR"] = remote_ip
    request.env["HTTP_USER_AGENT"] = user_agent
    request
  end

  before do
    Auth::GeoEnricher.reset_deferred!
    allow(Auth::GeoEnricher).to receive(:db_available?).and_return(false)
  end

  describe ".call" do
    context "happy" do
      it "creates a Session row with state=pending_approval and a 10-min window" do
        record = described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip
        )
        expect(record.state_pending_approval?).to be true
        expect(record.approval_required_until).to be_within(2.seconds).of(
          Session::PENDING_APPROVAL_TTL.from_now
        )
      end

      it "writes a LoginAttempt row with result: pending_approval, reason: new_location_pending" do
        expect {
          described_class.call(
            user: user,
            request: fake_request,
            fingerprint_hash: fp,
            ip_prefix: ip
          )
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("pending_approval")
        expect(row.reason).to eq("new_location_pending")
        expect(row.user_id).to eq(user.id)
      end

      it "links the attempt row to the freshly-minted session" do
        record = described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip
        )
        row = LoginAttempt.recent.first
        expect(row.session_id).to eq(record.id)
      end
    end

    context "sad: anti-spam guard" do
      it "raises TooManyPending once the user has reached the cap" do
        Auth::SessionPendingApprover::MAX_ACTIVE_PENDING.times do
          create(:session, :pending, user: user)
        end

        expect {
          described_class.call(
            user: user,
            request: fake_request,
            fingerprint_hash: fp,
            ip_prefix: ip
          )
        }.to raise_error(Auth::SessionPendingApprover::TooManyPending)
      end

      it "does NOT count expired-pending rows toward the cap" do
        Auth::SessionPendingApprover::MAX_ACTIVE_PENDING.times do
          create(:session, :expired_pending, user: user)
        end

        expect {
          described_class.call(
            user: user,
            request: fake_request,
            fingerprint_hash: fp,
            ip_prefix: ip
          )
        }.not_to raise_error
      end
    end

    context "edge: clock-skew tolerance" do
      it "measures approval_required_until server-side, not from the request" do
        # The service uses Time.current, NOT any client-provided
        # timestamp. Set Time.current via Timecop and confirm the row
        # honours the server's clock.
        travel_to Time.parse("2026-05-11 14:00:00 UTC") do
          record = described_class.call(
            user: user,
            request: fake_request,
            fingerprint_hash: fp,
            ip_prefix: ip
          )
          expect(record.approval_required_until).to eq(Time.parse("2026-05-11 14:10:00 UTC"))
        end
      end
    end

    context "edge: missing inputs" do
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
end
