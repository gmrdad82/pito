require "rails_helper"

RSpec.describe Auth::AttemptPurger do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe "happy paths" do
    it "deletes rows matching result" do
      keep   = create(:login_attempt, :success)
      delete = create(:login_attempt) # default :failed

      result = described_class.call(filter: { result: "failed" })

      expect(result.deleted_count).to eq(1)
      expect(LoginAttempt.find_by(id: delete.id)).to be_nil
      expect(LoginAttempt.find_by(id: keep.id)).to be_present
    end

    it "deletes rows matching ip" do
      target = create(:login_attempt, ip: "9.9.9.9", ip_prefix: "9.9.9.0/24")
      keep   = create(:login_attempt)

      result = described_class.call(filter: { ip: "9.9.9.9" })

      expect(result.deleted_count).to eq(1)
      expect(LoginAttempt.find_by(id: target.id)).to be_nil
      expect(LoginAttempt.find_by(id: keep.id)).to be_present
    end

    it "deletes rows matching fingerprint" do
      target = create(:login_attempt, fingerprint_hash: "f" * 64)
      keep   = create(:login_attempt)

      result = described_class.call(filter: { fingerprint: "f" * 64 })

      expect(result.deleted_count).to eq(1)
      expect(LoginAttempt.find_by(id: target.id)).to be_nil
      expect(LoginAttempt.find_by(id: keep.id)).to be_present
    end

    it "deletes rows matching user_id" do
      target_user = create(:user)
      target = create(:login_attempt, user: target_user)
      keep   = create(:login_attempt)

      result = described_class.call(filter: { user_id: target_user.id })

      expect(result.deleted_count).to eq(1)
      expect(LoginAttempt.find_by(id: target.id)).to be_nil
      expect(LoginAttempt.find_by(id: keep.id)).to be_present
    end

    it "deletes rows in [since, until_ts] window" do
      old_row = travel_to(3.days.ago) { create(:login_attempt) }
      mid_row = travel_to(2.days.ago) { create(:login_attempt) }
      new_row = create(:login_attempt)

      result = described_class.call(
        filter: { since: 2.5.days.ago.iso8601, until_ts: 1.day.ago.iso8601 }
      )

      expect(result.deleted_count).to eq(1)
      expect(LoginAttempt.find_by(id: mid_row.id)).to be_nil
      expect(LoginAttempt.find_by(id: old_row.id)).to be_present
      expect(LoginAttempt.find_by(id: new_row.id)).to be_present
    end

    it "echoes the filter back in the result" do
      create(:login_attempt)
      result = described_class.call(filter: { result: "failed" })
      expect(result.filter[:result]).to eq("failed")
    end

    it "intersects filters AND-wise" do
      create(:login_attempt, :success, ip: "1.1.1.1", ip_prefix: "1.1.1.0/24")
      target = create(:login_attempt, ip: "1.1.1.1", ip_prefix: "1.1.1.0/24")

      result = described_class.call(filter: { result: "failed", ip: "1.1.1.1" })

      expect(result.deleted_count).to eq(1)
      expect(LoginAttempt.find_by(id: target.id)).to be_nil
    end
  end

  describe "sad paths" do
    it "raises EmptyFilter on an empty filter hash" do
      create(:login_attempt)
      expect {
        described_class.call(filter: {})
      }.to raise_error(described_class::EmptyFilter)
    end

    it "raises EmptyFilter when every filter value is blank" do
      create(:login_attempt)
      expect {
        described_class.call(filter: { result: "", ip: nil })
      }.to raise_error(described_class::EmptyFilter)
    end

    it "raises InvalidFilter on a malformed since" do
      expect {
        described_class.call(filter: { since: "garbage" })
      }.to raise_error(described_class::InvalidFilter, /since/)
    end

    it "raises InvalidFilter on a malformed until_ts" do
      expect {
        described_class.call(filter: { until_ts: "garbage" })
      }.to raise_error(described_class::InvalidFilter, /until_ts/)
    end
  end

  describe "edge cases" do
    it "returns deleted_count=0 when no rows match" do
      result = described_class.call(filter: { fingerprint: "z" * 64 })
      expect(result.deleted_count).to eq(0)
    end

    it "batches large delete sets" do
      stub_const("#{described_class}::BATCH_SIZE", 2)

      5.times { create(:login_attempt) }
      create(:login_attempt, :success)

      result = described_class.call(filter: { result: "failed" })

      expect(result.deleted_count).to eq(5)
      expect(LoginAttempt.failed).to be_empty
      expect(LoginAttempt.succeeded.count).to eq(1)
    end

    it "ignores unknown result enum values" do
      create(:login_attempt)
      expect {
        described_class.call(filter: { result: "bogus" })
      }.to raise_error(described_class::EmptyFilter)
    end
  end

  describe "scope safety (flaw checks)" do
    it "does not touch blocked_locations rows" do
      block_row = create(:blocked_location)
      attempt   = create(:login_attempt, fingerprint_hash: "z" * 64)

      described_class.call(filter: { fingerprint: "z" * 64 })

      expect(BlockedLocation.find_by(id: block_row.id)).to be_present
      expect(LoginAttempt.find_by(id: attempt.id)).to be_nil
    end
  end
end
