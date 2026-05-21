require "rails_helper"

RSpec.describe Pito::Notifications::Source::ImportJobCompleted, type: :service do
  let(:user)    { create(:user) }
  let(:channel) { create(:channel, title: "My Channel") }

  def make_job(**attrs)
    ImportJob.create!({
      channel: channel,
      enqueued_by: user,
      status: :completed,
      started_at: 1.minute.ago,
      completed_at: Time.current,
      total_videos: 4,
      imported_videos: 4
    }.merge(attrs))
  end

  describe "happy path (completed)" do
    it "creates a Notification row tied to the enqueuing user" do
      job = make_job
      expect { described_class.report!(job) }.to change(Notification, :count).by(1)

      n = Notification.last
      expect(n.kind).to eq("import_job_completed")
      expect(n.severity).to eq("success")
      expect(n.event_type).to eq("import_job_completed")
      expect(n.dedup_key).to eq("import-job-#{job.id}")
      expect(n.title).to eq("import complete: My Channel (4 new)")
      expect(n.url).to eq("/imports/channels/#{job.id}")
      expect(n.created_by_user).to eq(user)
    end

    it "is idempotent on repeated report!" do
      job = make_job
      described_class.report!(job)
      expect { described_class.report!(job) }.not_to change(Notification, :count)
    end
  end

  describe "failed job" do
    it "renders the failure title and warn severity" do
      job = make_job(status: :failed,
                     error_payload: { "code" => "no_uploads_playlist", "message" => "missing" })
      described_class.report!(job)
      n = Notification.last
      expect(n.title).to start_with("import failed")
      expect(n.severity).to eq("warn")
      expect(n.body).to include("error: missing")
    end
  end

  describe "channel without a title" do
    it "falls back to the channel_url" do
      bare = create(:channel)
      job = make_job
      job.update_column(:channel_id, bare.id)
      job.reload
      described_class.report!(job)
      n = Notification.last
      expect(n.title).to include(bare.channel_url)
    end
  end
end
