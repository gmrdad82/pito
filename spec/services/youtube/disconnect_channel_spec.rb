require "rails_helper"

# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
# Disconnected state means `youtube_connection_id IS NULL`.
RSpec.describe Youtube::DisconnectChannel do
  before { GoogleStubs.stub_revoke_success }

  describe ".call" do
    it "clears youtube_connection_id on the Channel(s)" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      described_class.call(channel_ids: [ channel.id ])

      channel.reload
      expect(channel.youtube_connection_id).to be_nil
    end

    it "does not destroy the Channel record" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      expect {
        described_class.call(channel_ids: [ channel.id ])
      }.not_to change { Channel.unscoped.where(id: channel.id).exists? }
    end

    it "destroys the YoutubeConnection when no other Channel references it" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      expect {
        described_class.call(channel_ids: [ channel.id ])
      }.to change { YoutubeConnection.unscoped.where(id: connection.id).exists? }.from(true).to(false)
    end

    it "preserves the YoutubeConnection when other Channels reference it" do
      connection = create(:youtube_connection)
      kept = create(:channel, youtube_connection: connection)
      removed = create(:channel, youtube_connection: connection)

      described_class.call(channel_ids: [ removed.id ])

      expect(YoutubeConnection.unscoped.where(id: connection.id).exists?).to be(true)
      expect(kept.reload.youtube_connection_id).to eq(connection.id)
    end

    it "calls Google::RevokeToken once per orphaned connection" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      described_class.call(channel_ids: [ channel.id ])

      revoke_rows = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke")
      expect(revoke_rows.count).to eq(1)
    end

    it "supports bulk: 2+ channel ids transition atomically" do
      connection = create(:youtube_connection)
      a = create(:channel, youtube_connection: connection)
      b = create(:channel, youtube_connection: connection)

      described_class.call(channel_ids: [ a.id, b.id ])

      expect(a.reload.youtube_connection_id).to be_nil
      expect(b.reload.youtube_connection_id).to be_nil
      expect(YoutubeConnection.unscoped.where(id: connection.id).exists?).to be(false)
    end

    it "returns revoked_connection_ids in the Result struct" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      result = described_class.call(channel_ids: [ channel.id ])

      expect(result).to respond_to(:revoked_connection_ids)
      expect(result.revoked_connection_ids).to eq([ connection.id ])
      expect(result.disconnected_channel_ids).to eq([ channel.id ])
    end

    it "destroys the YoutubeConnection row when no channels remain" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      described_class.call(channel_ids: [ channel.id ])

      expect(YoutubeConnection.unscoped.where(id: connection.id)).to be_empty
    end
  end

  describe "already-revoked grant (idempotent path)" do
    before do
      WebMock.reset!
      GoogleStubs.stub_revoke_already_revoked
    end

    it "still destroys the local YoutubeConnection row" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      expect {
        described_class.call(channel_ids: [ channel.id ])
      }.to change { YoutubeConnection.unscoped.where(id: connection.id).exists? }.from(true).to(false)
    end

    it "audits the revoke as client_error" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      described_class.call(channel_ids: [ channel.id ])

      row = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").last
      expect(row.outcome).to eq("client_error")
    end
  end
end
