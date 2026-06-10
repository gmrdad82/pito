# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::HelpRenderer do
  def build_invocation(raw:, args: [])
    verb = raw.strip.split(/\s+/).first.delete_prefix("/").to_sym
    Pito::Slash::Invocation.new(verb:, args:, kwargs: {}, raw:)
  end

  describe ".call — /help --help (nonsense dictionary)" do
    subject(:result) do
      described_class.call(
        invocation: build_invocation(raw: "/help --help"),
        authenticated: true
      )
    end

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns exactly 1 event" do
      expect(result.events.size).to eq(1)
    end

    it "event is system kind" do
      expect(result.events.first[:kind]).to eq("system")
    end

    it "payload includes a body (the nonsense title)" do
      expect(result.events.first[:payload][:body]).to be_present
    end

    it "payload includes table_rows" do
      rows = result.events.first[:payload][:table_rows]
      expect(rows).to be_an(Array)
      expect(rows.size).to eq(10)
    end

    it "table_rows each have :key and :value" do
      rows = result.events.first[:payload][:table_rows]
      rows.each do |row|
        expect(row).to have_key(:key)
        expect(row).to have_key(:value)
      end
    end

    it "includes expected nonsense keys" do
      keys = result.events.first[:payload][:table_rows].map { |r| r[:key] }
      expect(keys).to include("/uninstall reality")
      expect(keys).to include("--help --help")
      expect(keys).to include("set brain.cells=∞")
    end
  end

  describe ".call — /themes --help (same nonsense easter egg)" do
    subject(:result) do
      described_class.call(
        invocation: build_invocation(raw: "/themes --help"),
        authenticated: true
      )
    end

    it "renders the identical nonsense payload as /help --help (themes is a bare sidebar opener)" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload]).to eq(described_class.nonsense_payload)
    end
  end

  describe ".call — /config igdb --help (provider key table)" do
    subject(:result) do
      described_class.call(
        invocation: build_invocation(raw: "/config igdb --help", args: [ "igdb" ]),
        authenticated: true
      )
    end

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "lists igdb keys as table_rows with '=' suffix" do
      rows = result.events.first[:payload][:table_rows]
      keys = rows.map { |r| r[:key] }
      expect(keys).to include("client_id=", "client_secret=")
    end

    it "does NOT include google-only keys" do
      rows = result.events.first[:payload][:table_rows]
      keys = rows.map { |r| r[:key] }
      expect(keys).not_to include("redirect_uri=", "api_key=")
    end

    it "row values are non-empty descriptions" do
      rows = result.events.first[:payload][:table_rows]
      rows.each do |row|
        expect(row[:value]).to be_present
      end
    end
  end

  describe ".call — /config voyage --help (provider key table)" do
    subject(:result) do
      described_class.call(
        invocation: build_invocation(raw: "/config voyage --help", args: [ "voyage" ]),
        authenticated: true
      )
    end

    it "lists only api_key as table row" do
      rows = result.events.first[:payload][:table_rows]
      keys = rows.map { |r| r[:key] }
      expect(keys).to eq([ "api_key=" ])
    end
  end

  describe ".call — /config webhook --help (provider key table)" do
    subject(:result) do
      described_class.call(
        invocation: build_invocation(raw: "/config webhook --help", args: [ "webhook" ]),
        authenticated: true
      )
    end

    it "lists slack and discord as table rows" do
      rows = result.events.first[:payload][:table_rows]
      keys = rows.map { |r| r[:key] }
      expect(keys).to include("slack=", "discord=")
    end
  end

  describe ".call — /config google --help (google provider table with suggestion)" do
    subject(:result) do
      described_class.call(
        invocation: build_invocation(raw: "/config google --help", args: [ "google" ]),
        authenticated: true
      )
    end

    it "includes google-specific keys" do
      rows = result.events.first[:payload][:table_rows]
      keys = rows.map { |r| r[:key] }
      expect(keys).to include("client_id=", "client_secret=", "redirect_uri=", "api_key=")
    end

    it "includes a /connect suggestion" do
      payload = result.events.first[:payload]
      expect(payload.dig(:suggestion, :run_cmd)).to eq("/connect")
    end
  end

  describe ".call — /config --help (general overview)" do
    subject(:result) do
      described_class.call(
        invocation: build_invocation(raw: "/config --help"),
        authenticated: true
      )
    end

    it "returns a body with the general usage pattern" do
      body = result.events.first[:payload][:body]
      expect(body).to include("/config")
    end

    it "lists all providers in table_rows" do
      keys = result.events.first[:payload][:table_rows].map { |r| r[:key] }
      expect(keys).to include("google", "voyage", "igdb", "webhook")
    end
  end

  describe ".call — /connect --help (generic command help)" do
    subject(:result) do
      described_class.call(
        invocation: build_invocation(raw: "/connect --help"),
        authenticated: true
      )
    end

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "includes usage info in the body" do
      body = result.events.first[:payload][:body]
      expect(body).to include("/connect")
    end

    it "does not start OAuth (returns a simple help event, not a redirect)" do
      # The result must be a plain Ok — not an OAuth URL or side-effect indicator.
      events = result.events
      expect(events.size).to eq(1)
      expect(events.first[:kind]).to eq("system")
    end
  end

  describe ".call — /login --help" do
    it "returns usage for login with code hint" do
      result = described_class.call(
        invocation: build_invocation(raw: "/login --help"),
        authenticated: false
      )
      expect(result).to be_a(Pito::Slash::Result::Ok)
      body = result.events.first[:payload][:body]
      expect(body).to include("/login")
    end
  end

  describe ".call — /disconnect --help" do
    it "returns usage for disconnect" do
      result = described_class.call(
        invocation: build_invocation(raw: "/disconnect --help"),
        authenticated: true
      )
      expect(result).to be_a(Pito::Slash::Result::Ok)
      body = result.events.first[:payload][:body]
      expect(body).to include("/disconnect")
    end
  end
end
