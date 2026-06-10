# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the OAuth refresh write path. Previously
# `apply_success!` wrote a non-existent `last_refreshed_at` column, so EVERY
# token refresh raised ActiveModel::UnknownAttributeError once the access token
# expired — silently breaking all YouTube API calls (sync, stats, analytics).
RSpec.describe Channel::Youtube::TokenRefresher, type: :service do
  let(:connection) do
    create(:youtube_connection,
           refresh_token: "refresh-abc",
           access_token:  "stale-token",
           expires_at:    1.hour.ago,
           needs_reauth:  false)
  end

  def fake_response(code:, body:)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.to_json)
  end

  before do
    allow(Pito::Credentials).to receive(:google_oauth_client_id).and_return("client-id")
    allow(Pito::Credentials).to receive(:google_oauth_client_secret).and_return("client-secret")
  end

  describe ".call — 200 success" do
    before do
      allow(described_class).to receive(:post_form).and_return(
        fake_response(code: 200, body: { "access_token" => "fresh-token", "expires_in" => 3600 })
      )
    end

    it "persists the refreshed token against the real schema (no last_refreshed_at column)" do
      expect { described_class.call(connection) }.not_to raise_error
      connection.reload
      expect(connection.access_token).to eq("fresh-token")
      expect(connection.expires_at).to be > Time.current
    end

    it "adopts a rotated refresh_token when Google returns one" do
      allow(described_class).to receive(:post_form).and_return(
        fake_response(code: 200, body: {
          "access_token" => "fresh-token", "expires_in" => 3600, "refresh_token" => "rotated-token"
        })
      )
      described_class.call(connection)
      expect(connection.reload.refresh_token).to eq("rotated-token")
    end
  end

  describe ".call — 400 invalid_grant" do
    before do
      allow(described_class).to receive(:post_form).and_return(
        fake_response(code: 400, body: { "error" => "invalid_grant" })
      )
    end

    it "flags the connection needs_reauth and raises NeedsReauthError" do
      expect { described_class.call(connection) }.to raise_error(Channel::Youtube::NeedsReauthError)
      expect(connection.reload.needs_reauth).to be true
    end
  end

  describe ".call — no refresh token on file" do
    it "raises NeedsReauthError without an HTTP call" do
      connection.update_columns(refresh_token: nil)
      expect { described_class.call(connection) }.to raise_error(Channel::Youtube::NeedsReauthError)
    end
  end
end
