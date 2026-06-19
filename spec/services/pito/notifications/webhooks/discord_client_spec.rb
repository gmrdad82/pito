# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::Webhooks::DiscordClient, type: :service do
  let(:webhook_url) { "https://discord.com/api/webhooks/123456789/abcdef_token" }
  subject(:client) { described_class.new(webhook_url) }

  # ---------------------------------------------------------------------------
  # #ping — payload shape
  # ---------------------------------------------------------------------------
  describe "#ping" do
    it "POSTs a JSON body with key 'content' wrapping the message" do
      captured_body = nil
      stub_request(:post, webhook_url)
        .with { |req| captured_body = req.body; true }
        .to_return(status: 204, body: "", headers: {})

      client.ping("hello world")

      parsed = JSON.parse(captured_body)
      expect(parsed).to eq({ "content" => "hello world" })
    end

    it "uses 'content' not 'text' (Discord key, not Slack key)" do
      captured_body = nil
      stub_request(:post, webhook_url)
        .with { |req| captured_body = req.body; true }
        .to_return(status: 204, body: "", headers: {})

      client.ping("check the key")

      parsed = JSON.parse(captured_body)
      expect(parsed).not_to have_key("text")
      expect(parsed).to have_key("content")
    end
  end

  # ---------------------------------------------------------------------------
  # #deliver — delegates straight to the POST path
  # ---------------------------------------------------------------------------
  describe "#deliver" do
    it "POSTs the payload as JSON" do
      captured_body = nil
      stub_request(:post, webhook_url)
        .with { |req| captured_body = req.body; true }
        .to_return(status: 204, body: "", headers: {})

      payload = { "embeds" => [ { "title" => "Weekly digest", "description" => "Stats here" } ] }
      client.deliver(payload)

      expect(JSON.parse(captured_body)).to eq(payload)
    end
  end

  # ---------------------------------------------------------------------------
  # 2xx response (Discord typically returns 204 No Content on webhook POST)
  # ---------------------------------------------------------------------------
  describe "2xx response" do
    before do
      stub_request(:post, webhook_url)
        .to_return(status: 204, body: "", headers: {})
    end

    it "returns a successful Result" do
      result = client.ping("test")
      expect(result.success?).to be true
    end

    it "sets status to the HTTP code" do
      result = client.ping("test")
      expect(result.status).to eq(204)
    end

    it "does not raise" do
      expect { client.ping("test") }.not_to raise_error
    end
  end

  context "with a 200 response body" do
    before do
      stub_request(:post, webhook_url)
        .to_return(status: 200, body: "ok", headers: { "Content-Type" => "application/json" })
    end

    it "sets body to the response body" do
      result = client.ping("test")
      expect(result.body).to eq("ok")
    end
  end

  # ---------------------------------------------------------------------------
  # Non-2xx response
  # ---------------------------------------------------------------------------
  describe "non-2xx response" do
    before do
      stub_request(:post, webhook_url)
        .to_return(status: 400, body: '{"message": "Unknown Webhook"}',
                   headers: { "Content-Type" => "application/json" })
    end

    it "returns a failure Result" do
      result = client.ping("test")
      expect(result.success?).to be false
    end

    it "sets status to the HTTP error code" do
      result = client.ping("test")
      expect(result.status).to eq(400)
    end

    it "includes the status code in the error message" do
      result = client.ping("test")
      expect(result.error).to include("400")
    end

    it "does not raise" do
      expect { client.ping("test") }.not_to raise_error
    end
  end

  context "with a 500 response" do
    before do
      stub_request(:post, webhook_url)
        .to_return(status: 500, body: "Internal Server Error", headers: {})
    end

    it "returns a failure Result with status 500" do
      result = client.deliver({ "content" => "msg" })
      expect(result.success?).to be false
      expect(result.status).to eq(500)
    end
  end

  # ---------------------------------------------------------------------------
  # Network failures
  # ---------------------------------------------------------------------------
  describe "network failures" do
    it "handles Net::OpenTimeout — returns failure Result without raising" do
      stub_request(:post, webhook_url).to_raise(Net::OpenTimeout.new("connection timed out"))

      result = nil
      expect { result = client.ping("test") }.not_to raise_error
      expect(result.success?).to be false
      expect(result.error).to start_with("timeout:")
    end

    it "handles Net::ReadTimeout — returns failure Result without raising" do
      stub_request(:post, webhook_url).to_raise(Net::ReadTimeout.new("read timed out"))

      result = nil
      expect { result = client.ping("test") }.not_to raise_error
      expect(result.success?).to be false
      expect(result.error).to start_with("timeout:")
    end

    it "handles SocketError (DNS failure) — returns failure Result without raising" do
      stub_request(:post, webhook_url).to_raise(SocketError.new("getaddrinfo: Name or service not known"))

      result = nil
      expect { result = client.ping("test") }.not_to raise_error
      expect(result.success?).to be false
      expect(result.error).to start_with("DNS failure:")
    end

    it "handles OpenSSL::SSL::SSLError — returns failure Result without raising" do
      stub_request(:post, webhook_url).to_raise(OpenSSL::SSL::SSLError.new("SSL_connect returned=1"))

      result = nil
      expect { result = client.ping("test") }.not_to raise_error
      expect(result.success?).to be false
      expect(result.error).to start_with("TLS failure:")
    end

    it "handles unexpected StandardError — returns failure Result without raising" do
      stub_request(:post, webhook_url).to_raise(StandardError.new("something blew up"))

      result = nil
      expect { result = client.ping("test") }.not_to raise_error
      expect(result.success?).to be false
      expect(result.error).to start_with("network error:")
    end

    it "leaves error.status nil on network failure" do
      stub_request(:post, webhook_url).to_raise(Net::ReadTimeout.new("timed out"))

      result = client.ping("test")
      expect(result.status).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # URL guard — non-HTTPS / invalid URLs never hit the network
  # ---------------------------------------------------------------------------
  describe "URL guard" do
    it "rejects an HTTP (non-HTTPS) URL without making a request" do
      http_client = described_class.new("http://discord.com/api/webhooks/123456789/abcdef_token")

      result = http_client.ping("test")

      expect(result.success?).to be false
      expect(result.error).to eq("invalid webhook URL")
      expect(a_request(:post, /.*/)).not_to have_been_made
    end

    it "rejects a blank/empty URL without making a request" do
      blank_client = described_class.new("")

      result = blank_client.ping("test")

      expect(result.success?).to be false
      expect(result.error).to eq("invalid webhook URL")
      expect(a_request(:post, /.*/)).not_to have_been_made
    end

    it "rejects a URL with no host without making a request" do
      no_host_client = described_class.new("https://")

      result = no_host_client.ping("test")

      expect(result.success?).to be false
      expect(result.error).to eq("invalid webhook URL")
      expect(a_request(:post, /.*/)).not_to have_been_made
    end
  end
end
