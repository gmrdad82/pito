require "rails_helper"

# Phase 7 Path A2 (literal full retract). The legacy `connected`
# boolean is gone; "disconnected" means `oauth_identity_id IS NULL`.
RSpec.describe Youtube::DisconnectChannel do
  before { GoogleStubs.stub_revoke_success }

  describe ".call" do
    it "clears oauth_identity_id on the Channel(s)" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)

      described_class.call(channel_ids: [ channel.id ])

      channel.reload
      expect(channel.oauth_identity_id).to be_nil
    end

    it "does not destroy the Channel record" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)

      expect {
        described_class.call(channel_ids: [ channel.id ])
      }.not_to change { Channel.unscoped.where(id: channel.id).exists? }
    end

    it "destroys the GoogleIdentity when no other Channel references it" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)

      expect {
        described_class.call(channel_ids: [ channel.id ])
      }.to change { GoogleIdentity.unscoped.where(id: identity.id).exists? }.from(true).to(false)
    end

    it "preserves the GoogleIdentity when other Channels reference it" do
      identity = create(:google_identity)
      kept = create(:channel, oauth_identity: identity)
      removed = create(:channel, oauth_identity: identity)

      described_class.call(channel_ids: [ removed.id ])

      expect(GoogleIdentity.unscoped.where(id: identity.id).exists?).to be(true)
      expect(kept.reload.oauth_identity_id).to eq(identity.id)
    end

    it "calls Google::RevokeToken once per orphaned identity" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)

      described_class.call(channel_ids: [ channel.id ])

      revoke_rows = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke")
      expect(revoke_rows.count).to eq(1)
    end

    it "supports bulk: 2+ channel ids transition atomically" do
      identity = create(:google_identity)
      a = create(:channel, oauth_identity: identity)
      b = create(:channel, oauth_identity: identity)

      described_class.call(channel_ids: [ a.id, b.id ])

      expect(a.reload.oauth_identity_id).to be_nil
      expect(b.reload.oauth_identity_id).to be_nil
      expect(GoogleIdentity.unscoped.where(id: identity.id).exists?).to be(false)
    end
  end

  describe "already-revoked grant (idempotent path)" do
    before do
      WebMock.reset!
      GoogleStubs.stub_revoke_already_revoked
    end

    it "still destroys the local GoogleIdentity row" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)

      expect {
        described_class.call(channel_ids: [ channel.id ])
      }.to change { GoogleIdentity.unscoped.where(id: identity.id).exists? }.from(true).to(false)
    end

    it "audits the revoke as client_error" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)

      described_class.call(channel_ids: [ channel.id ])

      row = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").last
      expect(row.outcome).to eq("client_error")
    end
  end
end
