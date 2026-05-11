require "rails_helper"

# Phase 22 §6.1 — Channel::ImportVideosJob.
RSpec.describe Channel::ImportVideosJob, type: :job do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection) }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:import_job) do
    ImportJob.create!(channel: channel, enqueued_by: user, status: :queued)
  end

  # Tiny double for `Channels::VideoImporter`. The job's
  # `build_importer` seam is stubbed to return this.
  class FakeImporter
    def initialize(behavior: :ok, total: 3, imported: 3)
      @behavior = behavior
      @total = total
      @imported = imported
    end

    def call(channel:, import_job:)
      case @behavior
      when :ok
        ImportJob.where(id: import_job.id).update_all(
          "total_videos = #{@total}, imported_videos = #{@imported}"
        )
        import_job.reload
        yield Channels::VideoImporter::PageProgress.new(total: @total, imported: @imported) if block_given?
      when :fatal
        raise Channels::VideoImporter::FatalError.new(
          code: :no_uploads_playlist, message: "boom", suppress_retry: true
        )
      when :transient
        raise Channels::VideoImporter::TransientError.new(code: :rate_limited, message: "429")
      end
    end
  end

  before do
    allow_any_instance_of(described_class).to receive(:build_importer)
      .and_return(FakeImporter.new(behavior: :ok))
  end

  describe "happy path" do
    it "transitions queued → running → completed and updates counters" do
      described_class.new.perform(channel.id, import_job.id)
      import_job.reload
      expect(import_job.status).to eq("completed")
      expect(import_job.imported_videos).to eq(3)
      expect(import_job.total_videos).to eq(3)
      expect(import_job.started_at).to be_present
      expect(import_job.completed_at).to be_present
    end

    it "dispatches a completion notification on success" do
      expect {
        described_class.new.perform(channel.id, import_job.id)
      }.to change(Notification, :count).by(1)

      notif = Notification.last
      expect(notif.kind).to eq("import_job_completed")
      expect(notif.severity).to eq("success")
      expect(notif.dedup_key).to eq("import-job-#{import_job.id}")
      expect(notif.created_by_user).to eq(user)
    end
  end

  describe "fatal error" do
    before do
      allow_any_instance_of(described_class).to receive(:build_importer)
        .and_return(FakeImporter.new(behavior: :fatal))
    end

    it "marks the ImportJob failed and captures error_payload" do
      expect {
        described_class.new.perform(channel.id, import_job.id)
      }.not_to raise_error

      import_job.reload
      expect(import_job.status).to eq("failed")
      expect(import_job.error_payload).to eq({ "code" => "no_uploads_playlist", "message" => "boom" })
      expect(import_job.completed_at).to be_present
    end

    it "dispatches a failure notification with warn severity" do
      described_class.new.perform(channel.id, import_job.id)
      notif = Notification.last
      expect(notif.kind).to eq("import_job_completed")
      expect(notif.severity).to eq("warn")
      expect(notif.title).to include("import failed")
    end

    it "does NOT re-raise (suppress_retry)" do
      expect {
        described_class.new.perform(channel.id, import_job.id)
      }.not_to raise_error
    end
  end

  describe "transient error" do
    before do
      allow_any_instance_of(described_class).to receive(:build_importer)
        .and_return(FakeImporter.new(behavior: :transient))
    end

    it "re-raises so Sidekiq retries" do
      expect {
        described_class.new.perform(channel.id, import_job.id)
      }.to raise_error(Channels::VideoImporter::TransientError)

      # The job did NOT mark the ImportJob terminal — it just bubbled
      # the error so Sidekiq's retry machinery fires.
      import_job.reload
      expect(import_job.status).to eq("running")
    end
  end

  describe "missing channel between enqueue and perform" do
    it "marks the ImportJob failed with channel_missing" do
      described_class.new.perform(999_999, import_job.id)
      import_job.reload
      expect(import_job.status).to eq("failed")
      expect(import_job.error_payload["code"]).to eq("channel_missing")
    end
  end

  describe "missing ImportJob row" do
    it "no-ops without raising" do
      expect {
        described_class.new.perform(channel.id, 999_999)
      }.not_to raise_error
    end
  end

  describe "Sidekiq.testing! enqueue" do
    it "is enqueued by Channel::ImportVideosJob.perform_async" do
      expect {
        described_class.perform_async(channel.id, import_job.id)
      }.to change(described_class.jobs, :size).by(1)
    end
  end
end
