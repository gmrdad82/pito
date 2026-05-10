require "rails_helper"

# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
# `Google::RevokeToken` accepts a `youtube_connection`; the audit
# row's column is `youtube_connection_id`.
RSpec.describe Google::RevokeToken do
  let(:connection) { create(:youtube_connection) }

  describe ".call" do
    context "on 200 success" do
      before { GoogleStubs.stub_revoke_success }

      it "writes an audit row with outcome=success" do
        expect {
          described_class.call(connection)
        }.to change { YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").count }.by(1)

        row = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").last
        expect(row.outcome).to eq("success")
        expect(row.http_status).to eq(200)
        expect(row.youtube_connection_id).to eq(connection.id)
      end

      it "returns true" do
        expect(described_class.call(connection)).to be(true)
      end
    end

    context "on already-revoked (idempotent path)" do
      before { GoogleStubs.stub_revoke_already_revoked }

      it "writes an audit row with outcome=client_error and error message" do
        described_class.call(connection)
        row = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").last
        expect(row.outcome).to eq("client_error")
        expect(row.error_message).to include("token already invalid")
      end

      it "returns true (does not raise)" do
        expect(described_class.call(connection)).to be(true)
      end
    end

    context "on network error" do
      before do
        WebMock.stub_request(:post, GoogleStubs::REVOKE_ENDPOINT)
          .to_raise(Errno::ECONNREFUSED.new("connection refused"))
      end

      it "writes an audit row with outcome=network_error and returns true" do
        expect(described_class.call(connection)).to be(true)
        row = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").last
        expect(row.outcome).to eq("network_error")
      end
    end
  end
end
