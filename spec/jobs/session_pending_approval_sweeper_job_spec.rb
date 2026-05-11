require "rails_helper"

# Phase 25 — 01b. Sweeper job spec.
RSpec.describe SessionPendingApprovalSweeperJob, type: :job do
  let(:user) { create(:user) }

  describe "#perform" do
    it "delegates to Auth::PendingSessionExpirer.call" do
      expect(Auth::PendingSessionExpirer).to receive(:call).and_return(0)
      described_class.new.perform
    end

    it "transitions every expired-pending row in one pass" do
      create_list(:session, 4, :expired_pending, user: user)
      expect { described_class.new.perform }.to change(Session.state_expired, :count).by(4)
    end

    it "is scheduled at the 1-minute cron via sidekiq-cron" do
      schedule_path = Rails.root.join("config/sidekiq_cron.yml")
      schedule = YAML.safe_load_file(schedule_path)
      entry = schedule["pending_session_approval_sweeper"]
      expect(entry).to be_present
      expect(entry["cron"]).to eq("* * * * *")
      expect(entry["class"]).to eq("SessionPendingApprovalSweeperJob")
    end
  end
end
