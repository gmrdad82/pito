require "rails_helper"

# Phase 25 — 01b. PendingSessionExpirer specs.
RSpec.describe Auth::PendingSessionExpirer do
  let(:user) { create(:user) }

  describe ".call" do
    context "happy: expired pending → :expired" do
      it "flips state to :expired" do
        session = create(:session, :expired_pending, user: user)
        expect { described_class.call }.to change { session.reload.state }.from("pending_approval").to("expired")
      end

      it "writes a LoginAttempt row with reason: pending_expired" do
        session = create(:session, :expired_pending, user: user)
        expect { described_class.call }.to change(LoginAttempt, :count).by(1)
        row = LoginAttempt.recent.first
        expect(row.reason).to eq("pending_expired")
        expect(row.session_id).to eq(session.id)
      end

      it "returns the count of transitioned rows" do
        create_list(:session, 3, :expired_pending, user: user)
        expect(described_class.call).to eq(3)
      end
    end

    context "happy: in-window pending row" do
      it "is untouched" do
        session = create(:session, :pending, user: user)
        expect { described_class.call }.not_to change { session.reload.state }
      end
    end

    context "edge: already-expired row" do
      it "is a no-op (does NOT write an attempt row)" do
        create(:session, :expired, user: user)
        expect { described_class.call }.not_to change(LoginAttempt, :count)
      end
    end

    context "edge: bulk run with 100 rows" do
      it "transitions all of them in one pass" do
        100.times { create(:session, :expired_pending, user: user) }
        expect { described_class.call }.to change(Session.state_expired, :count).by(100)
      end
    end

    context "sad: one bad row does not stop the sweep" do
      it "logs and continues past a row that raises" do
        good_a = create(:session, :expired_pending, user: user)
        bad    = create(:session, :expired_pending, user: user)
        good_b = create(:session, :expired_pending, user: user)

        # Force the middle row to raise on the transition. We stub
        # `expire_if_overdue!` so the iteration order doesn't matter.
        allow_any_instance_of(Session).to receive(:expire_if_overdue!).and_wrap_original do |orig, *args|
          if Current.respond_to?(:_test_bad_id) && orig.receiver.id == bad.id
            raise StandardError, "boom"
          end
          orig.call(*args)
        end

        # Use a module variable instead of Current (which doesn't have
        # arbitrary attributes). Simpler: rebuild without Current.
        allow_any_instance_of(Session).to receive(:expire_if_overdue!).and_wrap_original do |orig, *args|
          if orig.receiver.id == bad.id
            raise StandardError, "boom"
          end
          orig.call(*args)
        end

        described_class.call

        expect(good_a.reload.state_expired?).to be true
        expect(good_b.reload.state_expired?).to be true
        expect(bad.reload.state_pending_approval?).to be true
      end
    end
  end
end
