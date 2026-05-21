require "rails_helper"

# Phase 26 — 01b. Slack webhook HTTP client. `#ping` covers the
# Settings-pane test-ping path; `#deliver` covers the Phase 26 01e
# digest delivery path. Both wrap `Net::HTTP` and route every failure
# (network, malformed URL, non-2xx) through the `Result` struct so the
# caller never needs `rescue` boilerplate.
RSpec.describe Pito::Notifications::Webhooks::SlackClient do
  let(:webhook_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:client) { described_class.new(webhook_url) }

  describe "#ping" do
    it "POSTs `{ text: ... }` to the webhook URL" do
      stub = stub_request(:post, webhook_url)
        .with(headers: { "Content-Type" => "application/json" },
              body: { "text" => "hi" }.to_json)
        .to_return(status: 200, body: "ok")
      result = client.ping("hi")
      expect(stub).to have_been_requested
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

    it "returns a failed Result on 404" do
      stub_request(:post, webhook_url).to_return(status: 404, body: "")
      result = client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.status).to eq(404)
      expect(result.error).to include("HTTP 404")
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
      http_client = described_class.new("http://hooks.slack.com/services/T/B/x")
      result = http_client.ping("hi")
      expect(result.success?).to be(false)
      expect(result.error).to include("invalid webhook URL")
    end

    it "returns a failed Result for a blank URL" do
      blank_client = described_class.new("")
      result = blank_client.ping("hi")
      expect(result.success?).to be(false)
    end
  end

  describe "#deliver" do
    let(:payload) { { "text" => "real message", "blocks" => [] } }

    it "POSTs the payload as JSON" do
      stub = stub_request(:post, webhook_url)
        .with(headers: { "Content-Type" => "application/json" },
              body: payload.to_json)
        .to_return(status: 200, body: "ok")
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
      result = Pito::Notifications::Webhooks::SlackClient::Result.new(success: true)
      expect(result.success?).to be(true)
      result = Pito::Notifications::Webhooks::SlackClient::Result.new(success: false)
      expect(result.success?).to be(false)
    end
  end

  describe "timeouts" do
    it "sets open/read/write/ssl timeouts on the Net::HTTP instance" do
      stub_request(:post, webhook_url).to_return(status: 200, body: "ok")
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
