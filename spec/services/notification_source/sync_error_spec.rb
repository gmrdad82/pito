require "rails_helper"

RSpec.describe NotificationSource::SyncError do
  describe ".report!" do
    it "inserts a row with severity :urgent and event_type sync_error" do
      n = described_class.report!(
        job: ChannelSync,
        error: StandardError.new("boom"),
        dedup_key: "channel-sync-1-#{Date.current}"
      )
      expect(n).to be_persisted
      expect(n.event_type).to eq("sync_error")
      expect(n.urgent?).to be(true)
    end

    it "stores the job class name and error message in event_payload" do
      n = described_class.report!(
        job: ChannelSync,
        error: ArgumentError.new("bad arg"),
        dedup_key: "k1"
      )
      expect(n.event_payload["job_class"]).to eq("ChannelSync")
      expect(n.event_payload["error_class"]).to eq("ArgumentError")
      expect(n.event_payload["error_message"]).to eq("bad arg")
    end

    it "is idempotent on a second call with the same dedup_key" do
      key = "same-key"
      n1 = described_class.report!(job: ChannelSync, error: StandardError.new("x"), dedup_key: key)
      expect {
        n2 = described_class.report!(job: ChannelSync, error: StandardError.new("y"), dedup_key: key)
        expect(n2.id).to eq(n1.id)
      }.not_to change(Notification, :count)
    end

    it "produces distinct rows for different dedup_keys" do
      n1 = described_class.report!(job: ChannelSync, error: StandardError.new("x"), dedup_key: "k-a")
      n2 = described_class.report!(job: ChannelSync, error: StandardError.new("y"), dedup_key: "k-b")
      expect(n1.id).not_to eq(n2.id)
    end

    it "leaves created_by_user_id NULL (system-generated)" do
      n = described_class.report!(job: ChannelSync, error: StandardError.new("x"), dedup_key: "k-c")
      expect(n.created_by_user_id).to be_nil
    end

    it "accepts a string job name" do
      n = described_class.report!(
        job: "Some::Job",
        error: StandardError.new("x"),
        dedup_key: "k-string"
      )
      expect(n.event_payload["job_class"]).to eq("Some::Job")
    end
  end
end
