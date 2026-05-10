require "rails_helper"

RSpec.describe VideoSyncBack, type: :job do
  let(:user) { User.first || create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) { create(:video, channel: channel) }

  describe "happy path" do
    it "stamps last_synced_at + etag + clears last_sync_error" do
      reader = instance_double(Youtube::VideosReader)
      client = instance_double(Youtube::VideosClient)
      allow(Youtube::VideosReader).to receive(:new).and_return(reader)
      allow(Youtube::VideosClient).to receive(:new).and_return(client)
      allow(reader).to receive(:read_video).and_return(snippet: { title: "fresh" }, status: { madeForKids: false })
      allow(client).to receive(:update_video).and_return(etag: "new-etag", status: { madeForKids: true })

      video.update_columns(last_sync_error: "old")
      described_class.new.perform(video.id)
      v = video.reload
      expect(v.last_synced_at).to be_within(2.seconds).of(Time.current)
      expect(v.etag).to eq("new-etag")
      expect(v.last_sync_error).to be_nil
      expect(v.made_for_kids_effective).to be(true)
    end
  end

  describe "no connection" do
    it "stamps last_sync_error and does NOT call the API" do
      bare_channel = create(:channel, youtube_connection: nil)
      v = create(:video, channel: bare_channel)
      expect(Youtube::VideosReader).not_to receive(:new)

      described_class.new.perform(v.id)
      expect(v.reload.last_sync_error).to include("no youtube connection")
    end
  end

  describe "needs_reauth connection" do
    it "stamps last_sync_error and does NOT call the API" do
      connection.update!(needs_reauth: true)
      expect(Youtube::VideosReader).not_to receive(:new)

      described_class.new.perform(video.id)
      expect(video.reload.last_sync_error).to include("needs re-auth")
    end
  end

  describe "quota exceeded" do
    it "stamps last_sync_error and re-raises" do
      reader = instance_double(Youtube::VideosReader)
      allow(Youtube::VideosReader).to receive(:new).and_return(reader)
      allow(reader).to receive(:read_video).and_raise(Youtube::QuotaExhaustedError, "out of quota")

      expect {
        described_class.new.perform(video.id)
      }.to raise_error(Youtube::QuotaExhaustedError)
      expect(video.reload.last_sync_error).to include("quota exceeded")
    end
  end

  describe "auth revoked" do
    it "flips connection.needs_reauth and stamps last_sync_error" do
      reader = instance_double(Youtube::VideosReader)
      allow(Youtube::VideosReader).to receive(:new).and_return(reader)
      allow(reader).to receive(:read_video).and_raise(Youtube::AuthRevokedError, "401 from videos.list")

      described_class.new.perform(video.id)
      expect(connection.reload.needs_reauth).to be(true)
      expect(video.reload.last_sync_error).to include("needs re-auth")
    end
  end

  describe "validation error" do
    it "stamps last_sync_error and does NOT re-raise" do
      reader = instance_double(Youtube::VideosReader)
      client = instance_double(Youtube::VideosClient)
      allow(Youtube::VideosReader).to receive(:new).and_return(reader)
      allow(Youtube::VideosClient).to receive(:new).and_return(client)
      allow(reader).to receive(:read_video).and_return(snippet: {}, status: {})
      allow(client).to receive(:update_video).and_raise(Youtube::ValidationError, "title exceeds 100")

      expect {
        described_class.new.perform(video.id)
      }.not_to raise_error
      expect(video.reload.last_sync_error).to include("title exceeds 100")
    end
  end

  describe "5xx server error" do
    it "stamps last_sync_error and re-raises so Sidekiq retries" do
      reader = instance_double(Youtube::VideosReader)
      allow(Youtube::VideosReader).to receive(:new).and_return(reader)
      allow(reader).to receive(:read_video).and_raise(Youtube::ServerError, "500 internal")

      expect {
        described_class.new.perform(video.id)
      }.to raise_error(Youtube::ServerError)
      expect(video.reload.last_sync_error).to include("server error")
    end
  end

  describe "not found" do
    it "stamps last_sync_error (non-retriable)" do
      reader = instance_double(Youtube::VideosReader)
      allow(Youtube::VideosReader).to receive(:new).and_return(reader)
      allow(reader).to receive(:read_video).and_raise(Youtube::NotFoundError, "gone")

      expect {
        described_class.new.perform(video.id)
      }.not_to raise_error
      expect(video.reload.last_sync_error).to include("not found on youtube")
    end
  end

  describe "network timeout" do
    it "stamps last_sync_error and re-raises" do
      reader = instance_double(Youtube::VideosReader)
      allow(Youtube::VideosReader).to receive(:new).and_return(reader)
      allow(reader).to receive(:read_video).and_raise(Net::ReadTimeout)

      expect {
        described_class.new.perform(video.id)
      }.to raise_error(Net::ReadTimeout)
      expect(video.reload.last_sync_error).to include("network error")
    end
  end

  describe "missing video" do
    it "returns without raising" do
      expect { described_class.new.perform(99999) }.not_to raise_error
    end
  end
end
