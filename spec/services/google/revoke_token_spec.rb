require "rails_helper"

RSpec.describe Google::RevokeToken do
  let(:identity) { create(:google_identity) }

  describe ".call" do
    context "on 200 success" do
      before { GoogleStubs.stub_revoke_success }

      it "writes an audit row with outcome=success" do
        expect {
          described_class.call(identity)
        }.to change { YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").count }.by(1)

        row = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").last
        expect(row.outcome).to eq("success")
        expect(row.http_status).to eq(200)
      end

      it "returns true" do
        expect(described_class.call(identity)).to be(true)
      end
    end

    context "on already-revoked (idempotent path)" do
      before { GoogleStubs.stub_revoke_already_revoked }

      it "writes an audit row with outcome=client_error and error message" do
        described_class.call(identity)
        row = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").last
        expect(row.outcome).to eq("client_error")
        expect(row.error_message).to include("token already invalid")
      end

      it "returns true (does not raise)" do
        expect(described_class.call(identity)).to be(true)
      end
    end

    context "on network error" do
      before do
        WebMock.stub_request(:post, GoogleStubs::REVOKE_ENDPOINT)
          .to_raise(Errno::ECONNREFUSED.new("connection refused"))
      end

      it "writes an audit row with outcome=network_error and returns true" do
        expect(described_class.call(identity)).to be(true)
        row = YoutubeApiCall.unscoped.where(endpoint: "oauth2.revoke").last
        expect(row.outcome).to eq("network_error")
      end
    end
  end
end
