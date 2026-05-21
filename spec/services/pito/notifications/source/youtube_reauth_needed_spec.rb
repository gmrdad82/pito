require "rails_helper"

RSpec.describe Pito::Notifications::Source::YoutubeReauthNeeded do
  let(:user) { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }

  describe ".report!" do
    it "inserts a row with severity :urgent and event_type youtube_reauth_needed" do
      n = described_class.report!(connection)
      expect(n).to be_persisted
      expect(n.event_type).to eq("youtube_reauth_needed")
      expect(n.urgent?).to be(true)
    end

    it "uses dedup_key 'youtube-reauth-{id}'" do
      n = described_class.report!(connection)
      expect(n.dedup_key).to eq("youtube-reauth-#{connection.id}")
    end

    it "is idempotent on a second call for the same connection" do
      n1 = described_class.report!(connection)
      expect {
        n2 = described_class.report!(connection)
        expect(n2.id).to eq(n1.id)
      }.not_to change(Notification, :count)
    end

    it "produces distinct rows for different connections" do
      conn2 = create(:youtube_connection, user: user)
      n1 = described_class.report!(connection)
      n2 = described_class.report!(conn2)
      expect(n1.id).not_to eq(n2.id)
    end

    it "stores the connection email in event_payload" do
      n = described_class.report!(connection)
      expect(n.event_payload["connection_email"]).to eq(connection.email)
      expect(n.event_payload["connection_id"]).to eq(connection.id)
    end

    it "points url at the YouTube re-auth start route" do
      n = described_class.report!(connection)
      expect(n.url).to eq("/oauth/youtube/start")
    end

    it "stamps fires_at near Time.current" do
      Timecop.freeze do
        n = described_class.report!(connection)
        expect(n.fires_at).to be_within(1.second).of(Time.current)
      end
    rescue NameError
      # Timecop not loaded — fall back to a tolerant check.
      n = described_class.report!(connection)
      expect(n.fires_at).to be_within(2.seconds).of(Time.current)
    end
  end
end
