require "rails_helper"

# Phase 25 — 01b. SessionPendingApprover specs.
RSpec.describe Auth::SessionPendingApprover do
  include ActiveSupport::Testing::TimeHelpers

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

    # P25 follow-up — F5. The cap check + insert must be race-free.
    # Without the `User.lock("FOR UPDATE")` advisory lock, two
    # concurrent password-correct attempts both read N=cap-1, both
    # insert → cap exceeded. The lock serializes the check + insert
    # per-user.
    context "race-free MAX_ACTIVE_PENDING (P25 F5)" do
      it "wraps the cap check + insert in a User.lock advisory transaction" do
        # White-box assertion: the service MUST call `User.lock(...)`
        # with a relation that finds the user before inserting. We
        # spy on the call chain so a future refactor that drops the
        # lock immediately surfaces.
        relation = double("UserLockRelation")
        allow(User).to receive(:lock).with("FOR UPDATE").and_return(relation)
        expect(relation).to receive(:find).with(user.id).and_return(user)
        described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip
        )
      end

      it "still respects the cap when the lock-guarded count crosses the threshold" do
        # The cap is enforced INSIDE the locked transaction now. Pre-
        # seeding the cap should still raise even with the lock in
        # place (regression on the locked branch).
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

      it "rolls back the session row when the cap raise fires inside the locked transaction" do
        # Inserting N pending rows OUTSIDE the transaction then driving
        # the service must raise without persisting a (N+1)th row —
        # the lock+raise rolls back any partial state.
        Auth::SessionPendingApprover::MAX_ACTIVE_PENDING.times do
          create(:session, :pending, user: user)
        end
        expect {
          begin
            described_class.call(
              user: user,
              request: fake_request,
              fingerprint_hash: fp,
              ip_prefix: ip
            )
          rescue Auth::SessionPendingApprover::TooManyPending
            nil
          end
        }.not_to change { Session.pending.count }
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

    # Phase 25 — 01c. Pending creation fires the urgent notification
    # (LD-7). The dispatch lives outside the transaction so a
    # notification-helper failure cannot roll back the pending row.
    context "notification dispatch (Phase 25 — 01c)" do
      it "creates one Notification row with kind login_pending_approval" do
        expect {
          described_class.call(
            user: user,
            request: fake_request,
            fingerprint_hash: fp,
            ip_prefix: ip
          )
        }.to change(Notification.where(kind: :login_pending_approval), :count).by(1)
      end

      it "stamps the new notification with severity :urgent" do
        described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip
        )
        notification = Notification.where(kind: :login_pending_approval).last
        expect(notification.urgent?).to be true
      end

      it "links the attempt row to the new notification via notification_id" do
        described_class.call(
          user: user,
          request: fake_request,
          fingerprint_hash: fp,
          ip_prefix: ip
        )
        attempt = LoginAttempt.recent.first
        expect(attempt.notification_id).to be_present
      end

      it "still returns the pending session when the notification dispatch raises" do
        allow(NotificationSource::LoginPendingApproval).to receive(:report!).and_raise("boom")
        expect {
          described_class.call(
            user: user,
            request: fake_request,
            fingerprint_hash: fp,
            ip_prefix: ip
          )
        }.not_to raise_error
        expect(Session.pending.count).to eq(1)
      end
    end
  end
end
