require "rails_helper"

# Phase 26 — 01c. Discord webhook HTTP client. `#ping` covers the
# Settings-pane test-ping path; `#deliver` covers the Phase 26 01e
# digest delivery path. Both wrap `Net::HTTP` and route every failure
# (network, malformed URL, non-2xx) through the `Result` struct so the
# caller never needs `rescue` boilerplate.
#
# Discord-specific differences from `Webhooks::SlackClient`:
#
#   * `#ping` posts `{ "content": ... }` (Discord requires the
#     `content` field; Slack uses `text`).
#   * Both `discord.com` and `discordapp.com` host forms are valid
#     webhook targets. The legacy `discordapp.com` host is server-
#     side redirected to the canonical `discord.com` form; our client
#     passes through whichever the operator pasted.
#   * Successful Discord webhook calls return 204 No Content (Slack
#     returns 200 + "ok").
RSpec.describe Pito::Notifications::Webhooks::DiscordClient do
  let(:webhook_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }
  let(:client) { described_class.new(webhook_url) }

  describe "#ping" do
    it "POSTs `{ content: ... }` to the webhook URL" do
      stub = stub_request(:post, webhook_url)
        .with(headers: { "Content-Type" => "application/json" },
              body: { "content" => "hi" }.to_json)
        .to_return(status: 204, body: "")
      result = client.ping("hi")
      expect(stub).to have_been_requested
      expect(result.success?).to be(true)
      expect(result.status).to eq(204)
    end

    it "returns a successful Result on 200" do
      stub_request(:post, webhook_url).to_return(status: 200, body: "ok")
      result = client.ping("hi")
      expect(result.success?).to be(true)
      expect(result.status).to eq(200)
    end

    it "returns a successful Result on 204" do
      stub_request(:post, webhook_url).to_return(status: 204, body: "")
      result = client.ping("hi")
      expect(result.success?).to be(true)
      expect(result.status).to eq(204)
    end

    it "returns a failed Result on 400" do
      stub_request(:post, webhook_url).to_return(status: 400, body: "bad payload")
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.status).to eq(400)
      expect(result.error).to include("HTTP 400")
    end

    it "returns a failed Result on 401" do
      stub_request(:post, webhook_url).to_return(status: 401, body: "")
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.status).to eq(401)
      expect(result.error).to include("HTTP 401")
    end

    it "returns a failed Result on 404" do
      stub_request(:post, webhook_url).to_return(status: 404, body: "")
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.status).to eq(404)
      expect(result.error).to include("HTTP 404")
    end

    it "returns a failed Result on 429" do
      stub_request(:post, webhook_url).to_return(status: 429, body: "rate limited")
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.status).to eq(429)
      expect(result.error).to include("HTTP 429")
    end

    it "returns a failed Result on 500" do
      stub_request(:post, webhook_url).to_return(status: 500, body: "boom")
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.status).to eq(500)
      expect(result.error).to include("HTTP 500")
    end

    it "returns a failed Result on a connection timeout" do
      stub_request(:post, webhook_url).to_raise(::Net::OpenTimeout.new("connect"))
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.error).to include("timeout")
    end

    it "returns a failed Result on a read timeout" do
      stub_request(:post, webhook_url).to_raise(::Net::ReadTimeout.new("read"))
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.error).to include("timeout")
    end

    it "returns a failed Result on DNS failure" do
      stub_request(:post, webhook_url).to_raise(SocketError.new("getaddrinfo failed"))
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.error).to include("DNS")
    end

    it "returns a failed Result on a TLS failure" do
      stub_request(:post, webhook_url).to_raise(OpenSSL::SSL::SSLError.new("bad cert"))
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.error).to include("TLS")
    end

    it "returns a failed Result for a malformed URL" do
      bad_client = described_class.new("ht!tp://bad")
      result = bad_client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.error).to include("invalid webhook URL")
    end

    it "returns a failed Result for a non-HTTPS URL" do
      http_client = described_class.new("http://discord.com/api/webhooks/1/x")
      result = http_client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.error).to include("invalid webhook URL")
    end

    it "returns a failed Result for a blank URL" do
      blank_client = described_class.new("")
      result = blank_client.ping("hi")
      expect(result.success?).to be(false)
    end

    it "accepts the legacy discordapp.com host" do
      legacy = "https://discordapp.com/api/webhooks/123456789012345678/abc-DEF_xyz123"
      stub_request(:post, legacy).to_return(status: 204, body: "")
      result = described_class.new(legacy).ping("hi")
      expect(result.success?).to be(true)
    end
  end

  describe "#deliver" do
    let(:payload) { { "content" => "real message", "embeds" => [] } }

    it "POSTs the payload as JSON" do
      stub = stub_request(:post, webhook_url)
        .with(headers: { "Content-Type" => "application/json" },
              body: payload.to_json)
        .to_return(status: 204, body: "")
      result = client.deliver(payload)
      expect(stub).to have_been_requested
      expect(result.success?).to be(true)
    end

    it "returns a failed Result on non-2xx" do
      stub_request(:post, webhook_url).to_return(status: 500, body: "")
      result = client.deliver(payload)
      expect(result.success?).to be(false)
    end
  end

  describe "Result struct" do
    it "exposes `success?` predicate aligned to the `success` attribute" do
      result = Pito::Notifications::Webhooks::DiscordClient::Result.new(success: true)
      expect(result.success?).to be(true)
      result = Pito::Notifications::Webhooks::DiscordClient::Result.new(success: false)
      expect(result.success?).to be(false)
    end
  end

  describe "timeouts" do
    it "sets open/read/write/ssl timeouts on the Net::HTTP instance" do
      stub_request(:post, webhook_url).to_return(status: 204, body: "")
      captured = nil
      original_new = Net::HTTP.method(:new)
      allow(Net::HTTP).to receive(:new) do |*args|
        captured = original_new.call(*args)
        captured
      end
      client.ping("hi")
      expect(captured.open_timeout).to eq(described_class::OPEN_TIMEOUT)
      expect(captured.read_timeout).to eq(described_class::READ_TIMEOUT)
      expect(captured.write_timeout).to eq(described_class::WRITE_TIMEOUT)
      expect(captured.ssl_timeout).to eq(described_class::SSL_TIMEOUT)
    end
  end
end
