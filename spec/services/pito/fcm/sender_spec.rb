# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe Pito::Fcm::Sender, type: :service do
  # googleauth's ServiceAccountCredentials::TOKEN_CRED_URI (NOT the newer
  # oauth2.googleapis.com host — that's what UserRefreshCredentials/the
  # standalone Credentials class use; ServiceAccountCredentials hardcodes
  # this older googleapis.com host, verified against the installed gem).
  TOKEN_ENDPOINT = "https://www.googleapis.com/oauth2/v4/token"

  let(:project_id)   { "pito-test-project" }
  let(:send_endpoint) { "https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send" }
  let(:device_token) { "device-token-abc123" }

  # Synthetic, throwaway service-account fixture — a fresh RSA key generated
  # in-process, never anything copied from a real credential. The OAuth
  # handshake itself is entirely mocked over WebMock below, so the key only
  # needs to satisfy googleauth's JsonKeyReader shape (client_email +
  # private_key), not actually verify against Google.
  def write_fixture_credentials(project_id:)
    rsa_key = OpenSSL::PKey::RSA.new(2048)
    file = Tempfile.new([ "pito-fcm-fixture", ".json" ])
    file.write({
      type:                        "service_account",
      project_id:                  project_id,
      private_key_id:              "test-key-id",
      private_key:                 rsa_key.to_pem,
      client_email:                "pito-test@#{project_id}.iam.gserviceaccount.com",
      client_id:                   "000000000000000000000",
      auth_uri:                    "https://accounts.google.com/o/oauth2/auth",
      token_uri:                   TOKEN_ENDPOINT,
      auth_provider_x509_cert_url: "https://www.googleapis.com/oauth2/v1/certs",
      universe_domain:             "googleapis.com"
    }.to_json)
    file.flush
    file
  end

  def set_credentials_path(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PITO_FCM_CREDENTIALS_PATH").and_return(value)
  end

  def stub_token_endpoint(access_token: "fake-access-token")
    stub_request(:post, TOKEN_ENDPOINT).to_return(
      status:  200,
      body:    { access_token: access_token, expires_in: 3600, token_type: "Bearer" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  # The class-level memoized credentials (see Sender's file header — R3's
  # fanout instantiates a fresh Sender per device token, so the OAuth
  # credentials object is cached on the class, not the instance) must not
  # leak a fixture path or token between examples.
  around do |example|
    described_class.instance_variable_set(:@credentials, nil)
    example.run
    described_class.instance_variable_set(:@credentials, nil)
  end

  describe "#call" do
    context "when PITO_FCM_CREDENTIALS_PATH is blank" do
      before { set_credentials_path(nil) }

      it "returns a disabled outcome and makes no HTTP request" do
        stub = stub_request(:post, %r{.*})
        result = described_class.new.call(token: device_token, message: "hi")

        expect(result.success?).to be false
        expect(result.unregistered?).to be false
        expect(result.disabled?).to be true
        expect(stub).not_to have_been_requested
      end
    end

    context "when PITO_FCM_CREDENTIALS_PATH points at an unreadable path" do
      before { set_credentials_path("/nonexistent/pito-fcm-creds.json") }

      it "returns a disabled outcome and makes no HTTP request" do
        stub = stub_request(:post, %r{.*})
        result = described_class.new.call(token: device_token, message: "hi")

        expect(result.disabled?).to be true
        expect(stub).not_to have_been_requested
      end
    end

    context "when configured" do
      let(:fixture_file) { write_fixture_credentials(project_id: project_id) }

      before { set_credentials_path(fixture_file.path) }
      after { fixture_file.close! }

      context "happy path" do
        before do
          stub_token_endpoint
          stub_request(:post, send_endpoint).to_return(
            status:  200,
            body:    { name: "projects/#{project_id}/messages/0" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "returns a successful, non-unregistered, non-disabled outcome" do
          result = described_class.new.call(token: device_token, message: "hello", level: "warn")

          expect(result.success?).to be true
          expect(result.unregistered?).to be false
          expect(result.disabled?).to be false
        end

        it "sends a Bearer-authenticated, data-only message with no notification block" do
          sent_bodies = []
          sent_auth_headers = []
          stub_request(:post, send_endpoint).with do |request|
            sent_bodies << JSON.parse(request.body)
            sent_auth_headers << request.headers["Authorization"]
            true
          end.to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

          described_class.new.call(token: device_token, message: "hello", level: "warn")

          expect(sent_auth_headers).to eq([ "Bearer fake-access-token" ])
          expect(sent_bodies.length).to eq(1)
          expect(sent_bodies.first).to eq(
            "message" => {
              "token"   => device_token,
              "data"    => { "message" => "hello", "level" => "warn" },
              "android" => { "priority" => "high" }
            }
          )
          expect(sent_bodies.first["message"]).not_to have_key("notification")
        end

        it "includes data.title when a title is given" do
          sent_bodies = []
          stub_request(:post, send_endpoint).with do |request|
            sent_bodies << JSON.parse(request.body)
            true
          end.to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

          described_class.new.call(token: device_token, message: "hello", level: "warn", title: "Unpublished vids")

          expect(sent_bodies.first["message"]["data"]).to eq(
            "message" => "hello", "level" => "warn", "title" => "Unpublished vids"
          )
        end

        it "omits data.title entirely when title is nil" do
          sent_bodies = []
          stub_request(:post, send_endpoint).with do |request|
            sent_bodies << JSON.parse(request.body)
            true
          end.to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

          described_class.new.call(token: device_token, message: "hello", level: "warn", title: nil)

          expect(sent_bodies.first["message"]["data"]).not_to have_key("title")
        end

        it "omits data.title entirely when title is blank (never sends an empty string)" do
          sent_bodies = []
          stub_request(:post, send_endpoint).with do |request|
            sent_bodies << JSON.parse(request.body)
            true
          end.to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

          described_class.new.call(token: device_token, message: "hello", level: "warn", title: "")

          expect(sent_bodies.first["message"]["data"]).not_to have_key("title")
        end

        it "defaults level to info when not given" do
          sent_bodies = []
          stub_request(:post, send_endpoint).with do |request|
            sent_bodies << JSON.parse(request.body)
            true
          end.to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

          described_class.new.call(token: device_token, message: "hello")

          expect(sent_bodies.first["message"]["data"]).to eq("message" => "hello", "level" => "info")
        end
      end

      context "on a 404 response (dead token)" do
        before do
          stub_token_endpoint
          stub_request(:post, send_endpoint).to_return(
            status:  404,
            body:    { error: { code: 404, message: "Requested entity was not found.", status: "NOT_FOUND" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "returns a failed, unregistered outcome" do
          result = described_class.new.call(token: device_token, message: "hi")

          expect(result.success?).to be false
          expect(result.unregistered?).to be true
        end
      end

      context "on a 200-status-code error body whose error.status is UNREGISTERED" do
        before do
          stub_token_endpoint
          stub_request(:post, send_endpoint).to_return(
            status:  400,
            body:    { error: { code: 400, message: "not registered", status: "UNREGISTERED" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "returns a failed, unregistered outcome (error.status signal, not just 404)" do
          result = described_class.new.call(token: device_token, message: "hi")

          expect(result.success?).to be false
          expect(result.unregistered?).to be true
        end
      end

      context "on an error body carrying UNREGISTERED as an FcmError detail errorCode" do
        before do
          stub_token_endpoint
          stub_request(:post, send_endpoint).to_return(
            status:  400,
            body:    {
              error: {
                code:    400,
                message: "The registration token is not a valid FCM registration token",
                status:  "INVALID_ARGUMENT",
                details: [
                  { "@type" => "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode" => "UNREGISTERED" }
                ]
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "returns a failed, unregistered outcome" do
          result = described_class.new.call(token: device_token, message: "hi")

          expect(result.success?).to be false
          expect(result.unregistered?).to be true
        end
      end

      context "on a non-2xx response that is not the unregistered signature" do
        before do
          stub_token_endpoint
          stub_request(:post, send_endpoint).to_return(status: 500, body: "boom")
        end

        it "returns a failed, NON-unregistered outcome" do
          result = described_class.new.call(token: device_token, message: "hi")

          expect(result.success?).to be false
          expect(result.unregistered?).to be false
        end
      end

      context "on a transport error sending the FCM message" do
        before do
          stub_token_endpoint
          stub_request(:post, send_endpoint).to_timeout
        end

        it "returns a failed, non-unregistered outcome without raising" do
          result = nil
          expect { result = described_class.new.call(token: device_token, message: "hi") }.not_to raise_error

          expect(result.success?).to be false
          expect(result.unregistered?).to be false
          expect(result.disabled?).to be false
        end
      end

      context "on a transport error fetching the OAuth token" do
        before { stub_request(:post, TOKEN_ENDPOINT).to_timeout }

        it "returns a failed, non-unregistered outcome without raising" do
          result = nil
          expect { result = described_class.new.call(token: device_token, message: "hi") }.not_to raise_error

          expect(result.success?).to be false
          expect(result.unregistered?).to be false
        end
      end

      context "credentials memoization across calls" do
        before do
          stub_token_endpoint
          stub_request(:post, send_endpoint).to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })
        end

        it "fetches the OAuth token once and reuses it across multiple sends (class-level memoized credentials)" do
          described_class.new.call(token: device_token, message: "one")
          described_class.new.call(token: device_token, message: "two")

          expect(a_request(:post, TOKEN_ENDPOINT)).to have_been_made.once
          expect(a_request(:post, send_endpoint)).to have_been_made.times(2)
        end
      end
    end
  end
end
