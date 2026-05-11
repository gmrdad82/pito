require "rails_helper"

# Phase 25 — 01c. NotificationSource::LoginPendingApproval specs.
RSpec.describe NotificationSource::LoginPendingApproval do
  let(:user) { create(:user, email: "victim@example.test") }
  let(:pending) { create(:session, :pending, user: user) }
  let!(:attempt) do
    create(:login_attempt, :pending, :with_geo,
           user: user,
           browser: "Firefox",
           os: "Linux",
           ip: "10.0.0.5",
           ip_prefix: "10.0.0.0/24",
           fingerprint_hash: Digest::SHA256.hexdigest("nsl-fp"),
           session: pending,
           email_attempted: "victim@example.test")
  end

  describe ".report! (happy)" do
    it "inserts a notification with kind: login_pending_approval and severity: urgent" do
      expect {
        described_class.report!(attempt: attempt)
      }.to change(Notification, :count).by(1)

      n = Notification.last
      expect(n.event_type).to eq("login_pending_approval")
      expect(n.urgent?).to be true
      expect(n.kind).to eq("login_pending_approval")
    end

    it "stamps the event_payload with the row's identifying fields" do
      n = described_class.report!(attempt: attempt)
      payload = n.event_payload
      expect(payload["login_attempt_id"]).to eq(attempt.id)
      expect(payload["session_id"]).to eq(pending.id)
      expect(payload["user_id"]).to eq(user.id)
      expect(payload["email"]).to eq("victim@example.test")
      expect(payload["browser"]).to eq("Firefox")
      expect(payload["os"]).to eq("Linux")
      expect(payload["ip"]).to eq("10.0.0.5")
      expect(payload["ip_prefix"]).to eq("10.0.0.0/24")
      expect(payload["fingerprint_short"].length).to eq(12)
      expect(payload["geo_summary"]).to include("Bucharest")
    end

    it "stamps the notification_id FK on the source attempt row" do
      n = described_class.report!(attempt: attempt)
      expect(attempt.reload.notification_id).to eq(n.id)
    end

    it "uses dedup key based on login_attempt_id" do
      n = described_class.report!(attempt: attempt)
      expect(n.dedup_key).to eq("login-pending-#{attempt.id}")
    end
  end

  describe ".report! (idempotency / dedupe)" do
    it "returns the same notification row on a second call (no duplicate)" do
      n1 = described_class.report!(attempt: attempt)
      n2 = described_class.report!(attempt: attempt)
      expect(n2.id).to eq(n1.id)
    end

    it "does not raise when stamping notification_id twice (already set)" do
      n = described_class.report!(attempt: attempt)
      expect { described_class.report!(attempt: attempt) }.not_to raise_error
      expect(attempt.reload.notification_id).to eq(n.id)
    end

    it "creates a distinct row per attempt" do
      other_session = create(:session, :pending, user: user)
      other_attempt = create(:login_attempt, :pending,
                             user: user, session: other_session,
                             fingerprint_hash: Digest::SHA256.hexdigest("other-fp"),
                             ip_prefix: "10.0.0.0/24")

      n1 = described_class.report!(attempt: attempt)
      n2 = described_class.report!(attempt: other_attempt)
      expect(n1.id).not_to eq(n2.id)
    end
  end

  describe ".report! (sad)" do
    it "raises ArgumentError when attempt is nil" do
      expect {
        described_class.report!(attempt: nil)
      }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when attempt is not persisted" do
      expect {
        described_class.report!(attempt: LoginAttempt.new)
      }.to raise_error(ArgumentError)
    end
  end

  describe ".report! (template integration)" do
    it "renders an in-app payload from the new template" do
      n = described_class.report!(attempt: attempt)
      payload = NotificationFormatter::InApp.payload_for(n)
      expect(payload[:title]).to include("victim@example.test")
      expect(payload[:body_html]).to include("yeah, it&#39;s me").or include("yeah, it's me")
      expect(payload[:body_html]).to include("block the intruder")
      expect(payload[:url]).to eq("/notifications/#{n.id}")
      expect(payload[:severity]).to eq("urgent")
    end

    it "links the body to /login/approvals/:id and /login/blocks/:id" do
      n = described_class.report!(attempt: attempt)
      payload = NotificationFormatter::InApp.payload_for(n)
      expect(payload[:body_html]).to include("/login/approvals/#{attempt.id}")
      expect(payload[:body_html]).to include("/login/blocks/#{attempt.id}")
    end
  end
end
