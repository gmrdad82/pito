require "rails_helper"

# P25 follow-up — F6. PII retention sweep for `LoginAttempt` rows.
# Daily cron scrubs `email_attempted` on failed / invalid-password
# rows older than 90 days. Forensic columns (IP, fingerprint, geo)
# stay so the block-list inputs and audit trail survive.
RSpec.describe LoginAttemptPiiPurgeJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  describe "#perform" do
    it "scrubs email_attempted on a failed/wrong_password row older than 90 days" do
      stale = travel_to(95.days.ago) do
        create(:login_attempt,
               result: :failed,
               reason: :wrong_password,
               email_attempted: "leaked@example.test")
      end

      described_class.new.perform

      expect(stale.reload.email_attempted).to be_nil
      # Forensic columns survive.
      expect(stale.reload.ip).to be_present
      expect(stale.reload.fingerprint_hash).to be_present
    end

    it "scrubs email_attempted on a failed/unknown_account row older than 90 days" do
      stale = travel_to(95.days.ago) do
        create(:login_attempt,
               result: :failed,
               reason: :unknown_account,
               email_attempted: "unknown@example.test")
      end

      described_class.new.perform

      expect(stale.reload.email_attempted).to be_nil
    end

    it "does NOT scrub a failed/wrong_password row inside the retention window" do
      fresh = create(:login_attempt,
                     result: :failed,
                     reason: :wrong_password,
                     email_attempted: "fresh@example.test")
      described_class.new.perform
      expect(fresh.reload.email_attempted).to eq("fresh@example.test")
    end

    it "does NOT scrub success rows (the user already trusts us with their email)" do
      user = create(:user)
      stale_success = travel_to(95.days.ago) do
        create(:login_attempt,
               result: :success,
               reason: :trusted_location_success,
               user: user,
               email_attempted: "success@example.test")
      end
      described_class.new.perform
      expect(stale_success.reload.email_attempted).to eq("success@example.test")
    end

    it "does NOT scrub pending_approval rows (forensic value beyond 90 days)" do
      stale_pending = travel_to(95.days.ago) do
        create(:login_attempt,
               result: :pending_approval,
               reason: :new_location_pending,
               email_attempted: "pending@example.test")
      end
      described_class.new.perform
      expect(stale_pending.reload.email_attempted).to eq("pending@example.test")
    end

    it "does NOT scrub blocked rows (block-list audit trail)" do
      stale_blocked = travel_to(95.days.ago) do
        create(:login_attempt,
               result: :blocked,
               reason: :blocked_pair,
               email_attempted: "blocked@example.test")
      end
      described_class.new.perform
      expect(stale_blocked.reload.email_attempted).to eq("blocked@example.test")
    end

    it "does NOT scrub twofa_failed rows (user is already authenticated)" do
      user = create(:user)
      stale_twofa = travel_to(95.days.ago) do
        create(:login_attempt,
               result: :failed,
               reason: :twofa_failed,
               user: user,
               email_attempted: "twofa@example.test")
      end
      described_class.new.perform
      expect(stale_twofa.reload.email_attempted).to eq("twofa@example.test")
    end

    it "is a no-op when no rows match the purge criteria" do
      create(:login_attempt, result: :failed, reason: :wrong_password)
      expect(described_class.new.perform).to eq(0)
    end

    it "returns the count of purged rows" do
      travel_to(95.days.ago) do
        create_list(:login_attempt, 3,
                    result: :failed,
                    reason: :wrong_password,
                    email_attempted: "spam@example.test")
      end
      expect(described_class.new.perform).to eq(3)
    end

    it "logs the count" do
      travel_to(95.days.ago) do
        create(:login_attempt,
               result: :failed,
               reason: :wrong_password,
               email_attempted: "logged@example.test")
      end
      expect(Rails.logger).to receive(:info).with(/scrubbed email_attempted on 1 LoginAttempt row/)
      described_class.new.perform
    end

    it "uses the documented retention period (90 days)" do
      expect(described_class::RETENTION_PERIOD).to eq(90.days)
    end

    it "swallows transient DB errors per batch with a warn (defensive guard)" do
      travel_to(95.days.ago) do
        create(:login_attempt,
               result: :failed,
               reason: :wrong_password,
               email_attempted: "boom@example.test")
      end

      # Force the batch update to blow up.
      allow_any_instance_of(ActiveRecord::Relation)
        .to receive(:update_all)
        .and_raise(ActiveRecord::StatementInvalid.new("boom"))

      expect(Rails.logger).to receive(:warn).with(/batch failed.*StatementInvalid/)
      expect { described_class.new.perform }.not_to raise_error
    end

    it "handles a row whose created_at sits just past the cutoff" do
      stale = create(:login_attempt,
                     result: :failed,
                     reason: :wrong_password,
                     email_attempted: "edge@example.test")
      stale.update_column(:created_at, 90.days.ago - 1.second)
      described_class.new.perform
      expect(stale.reload.email_attempted).to be_nil
    end

    it "skips a row whose created_at sits just inside the cutoff" do
      borderline = create(:login_attempt,
                          result: :failed,
                          reason: :wrong_password,
                          email_attempted: "border@example.test")
      borderline.update_column(:created_at, 90.days.ago + 1.minute)
      described_class.new.perform
      expect(borderline.reload.email_attempted).to eq("border@example.test")
    end
  end

  describe "Sidekiq cron registration" do
    let(:cron_yaml) { YAML.load_file(Rails.root.join("config/sidekiq_cron.yml")) }

    it "is registered in config/sidekiq_cron.yml under `login_attempt_pii_purge`" do
      expect(cron_yaml).to have_key("login_attempt_pii_purge")
      expect(cron_yaml["login_attempt_pii_purge"]).to include(
        "class" => "LoginAttemptPiiPurgeJob"
      )
    end

    it "is scheduled daily at 04:00 UTC" do
      expect(cron_yaml["login_attempt_pii_purge"]["cron"]).to eq("0 4 * * *")
    end
  end
end
