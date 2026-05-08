require "rails_helper"

RSpec.describe Youtube::TokenRefresher do
  let(:identity) { create(:google_identity, :expired) }

  describe ".call" do
    context "on 200 success" do
      before do
        GoogleStubs.stub_refresh_success(
          access_token: "ya29.refreshed-access-token",
          expires_in: 3600
        )
      end

      it "updates access_token, expires_at, and last_refreshed_at" do
        described_class.call(identity)
        identity.reload
        expect(identity.access_token).to eq("ya29.refreshed-access-token")
        expect(identity.expires_at).to be > 30.minutes.from_now
        expect(identity.last_refreshed_at).to be_within(5.seconds).of(Time.current)
      end

      it "rotates the refresh_token when Google returns a new one" do
        WebMock.reset!
        GoogleStubs.stub_refresh_success(
          access_token: "ya29.fresh-access",
          refresh_token: "1//new-refresh-token-xyz"
        )

        described_class.call(identity)
        identity.reload
        expect(identity.refresh_token).to eq("1//new-refresh-token-xyz")
      end
    end

    context "on 400 invalid_grant" do
      before { GoogleStubs.stub_refresh_invalid_grant }

      it "sets needs_reauth and raises NeedsReauthError" do
        expect {
          described_class.call(identity)
        }.to raise_error(Youtube::NeedsReauthError)
        expect(identity.reload.needs_reauth?).to be(true)
      end
    end

    context "on 5xx" do
      before do
        WebMock.stub_request(:post, GoogleStubs::TOKEN_ENDPOINT)
          .to_return(status: 503, body: "{}", headers: { "Content-Type" => "application/json" })
      end

      it "raises TransientError" do
        expect {
          described_class.call(identity)
        }.to raise_error(Youtube::TransientError)
      end
    end

    context "with no refresh token on file" do
      let(:identity) { create(:google_identity, :no_refresh_token, :expired) }

      it "raises NeedsReauthError without hitting the network" do
        expect {
          described_class.call(identity)
        }.to raise_error(Youtube::NeedsReauthError)
      end
    end
  end
end
