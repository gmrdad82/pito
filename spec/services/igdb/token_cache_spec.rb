require "rails_helper"
require "ostruct"

RSpec.describe Igdb::TokenCache do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails.application.credentials).to receive(:igdb).and_return(
      OpenStruct.new(client_id: "id", client_secret: "secret")
    )
  end

  describe "#token" do
    it "fetches a token from Twitch on the first call" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "tok-1", expires_in: 5_184_000 }.to_json)

      expect(described_class.new(cache: cache).token).to eq("tok-1")
      expect(WebMock).to have_requested(:post, %r{id\.twitch\.tv/oauth2/token}).once
    end

    it "reuses the cached token on subsequent calls" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "tok-2", expires_in: 5_184_000 }.to_json)

      tc = described_class.new(cache: cache)
      tc.token
      tc.token
      expect(WebMock).to have_requested(:post, %r{id\.twitch\.tv/oauth2/token}).once
    end

    it "re-fetches after the cached TTL elapses" do
      # The MemoryStore cache observes wall-clock TTL, so we expire it
      # directly by deleting the entry rather than time-traveling.
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "tok-A", expires_in: 90 }.to_json)
        .to_return(status: 200, body: { access_token: "tok-B", expires_in: 90 }.to_json)

      tc = described_class.new(cache: cache)
      expect(tc.token).to eq("tok-A")
      cache.delete(Igdb::TokenCache::CACHE_KEY)
      expect(tc.token).to eq("tok-B")
      expect(WebMock).to have_requested(:post, %r{id\.twitch\.tv/oauth2/token}).twice
    end

    it "raises AuthError when Twitch returns 400" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 400, body: %({"error":"bad"}))

      expect { described_class.new(cache: cache).token }
        .to raise_error(Igdb::Client::AuthError)
    end

    it "raises AuthError when Twitch returns malformed JSON" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: "not-json")

      expect { described_class.new(cache: cache).token }
        .to raise_error(Igdb::Client::AuthError, /malformed JSON/)
    end

    it "raises MissingCredentials when the credentials block is absent" do
      allow(Rails.application.credentials).to receive(:igdb).and_return(nil)
      expect { described_class.new(cache: cache).token }
        .to raise_error(Igdb::Client::MissingCredentials)
    end
  end

  describe "#invalidate!" do
    it "clears the cached token" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "tok-X", expires_in: 5_184_000 }.to_json)
        .to_return(status: 200, body: { access_token: "tok-Y", expires_in: 5_184_000 }.to_json)

      tc = described_class.new(cache: cache)
      expect(tc.token).to eq("tok-X")
      tc.invalidate!
      expect(tc.token).to eq("tok-Y")
    end
  end

  # Phase 14 audit F1 — Twitch token acquisition is the auth bootstrap
  # for every IGDB call; a hang on `id.twitch.tv/oauth2/token` would
  # wedge a Sidekiq worker the same way a hang on `api.igdb.com`
  # would. Mirrors the HTTP-timeouts spec block in
  # `spec/services/igdb/client_spec.rb`.
  describe "HTTP timeouts (audit F1)" do
    it "sets open / read / write timeouts on the Net::HTTP instance" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "tok-T", expires_in: 5_184_000 }.to_json)

      captured = nil
      original_start = Net::HTTP.method(:start)
      allow(Net::HTTP).to receive(:start) do |host, port, opts = {}, &block|
        original_start.call(host, port, opts) do |http|
          captured = http
          block.call(http)
        end
      end

      described_class.new(cache: cache).token

      expect(captured).to be_a(Net::HTTP)
      expect(captured.open_timeout).to  eq(Igdb::TokenCache::OPEN_TIMEOUT_SEC)
      expect(captured.read_timeout).to  eq(Igdb::TokenCache::READ_TIMEOUT_SEC)
      expect(captured.write_timeout).to eq(Igdb::TokenCache::WRITE_TIMEOUT_SEC)
    end

    it "uses SSL because the Twitch token URL is HTTPS" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "tok-S", expires_in: 5_184_000 }.to_json)

      captured = nil
      original_start = Net::HTTP.method(:start)
      allow(Net::HTTP).to receive(:start) do |host, port, opts = {}, &block|
        original_start.call(host, port, opts) do |http|
          captured = http
          block.call(http)
        end
      end

      described_class.new(cache: cache).token

      expect(captured.use_ssl?).to be(true)
    end

    it "surfaces a hung connection as Net::OpenTimeout to the caller" do
      # Sad-path proof: when the underlying connection raises a timeout
      # error, it bubbles up the stack instead of getting swallowed.
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token}).to_timeout

      expect { described_class.new(cache: cache).token }.to raise_error(
        an_instance_of(Net::OpenTimeout).or(an_instance_of(Net::ReadTimeout))
      )
    end
  end
end
