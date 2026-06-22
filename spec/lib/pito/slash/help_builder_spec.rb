# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::HelpBuilder do
  def build_invocation(raw:, args: [])
    verb = raw.strip.split(/\s+/).first.delete_prefix("/").to_sym
    Pito::Slash::Invocation.new(verb:, args:, kwargs: {}, raw:)
  end

  # Every --help response must be a man-page block.
  shared_examples "man-page result" do
    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns exactly 1 system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq("system")
    end

    it "payload has html: true" do
      expect(result.events.first[:payload]["html"]).to be true
    end

    it "body contains .pito-help-block" do
      expect(result.events.first[:payload]["body"]).to include("pito-help-block")
    end

    it "body contains Usage:" do
      expect(result.events.first[:payload]["body"]).to include("Usage:")
    end
  end

  # ── /help --help (nonsense easter egg) ──────────────────────────────────────

  describe ".call — /help --help (nonsense man-page)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/help --help"))
    end

    include_examples "man-page result"

    it "body includes the manual's manual phrase" do
      expect(result.events.first[:payload]["body"]).to include("manual")
    end

    it "body includes nonsense Commands: section" do
      expect(result.events.first[:payload]["body"]).to include("Commands:")
    end

    it "body includes a sampling of nonsense rows" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("uninstall reality")
      expect(body).to include("touch grass")
    end
  end

  # ── /themes --help (same nonsense easter egg) ────────────────────────────────

  describe ".call — /themes --help" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/themes --help"))
    end

    it "renders the nonsense man page (themes is a bare sidebar opener)" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
      body = result.events.first[:payload]["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("manual")
    end
  end

  # ── .nonsense_body ──────────────────────────────────────────────────────────

  describe ".nonsense_body" do
    it "returns an html_safe String with .pito-help-block" do
      body = described_class.nonsense_body
      expect(body).to be_a(String)
      expect(body).to include("pito-help-block")
      expect(body).to include("manual")
    end
  end

  # ── /config igdb --help ──────────────────────────────────────────────────────

  describe ".call — /config igdb --help (provider key table)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/config igdb --help", args: [ "igdb" ]))
    end

    include_examples "man-page result"

    it "body includes igdb key tokens with = suffix" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("client_id=")
      expect(body).to include("client_secret=")
    end

    it "body does NOT include google-only keys" do
      body = result.events.first[:payload]["body"]
      expect(body).not_to include("redirect_uri=")
      expect(body).not_to include("api_key=")
    end

    it "body includes a Keys: section" do
      expect(result.events.first[:payload]["body"]).to include("Keys:")
    end
  end

  # ── /config voyage --help ────────────────────────────────────────────────────

  describe ".call — /config voyage --help (provider key table)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/config voyage --help", args: [ "voyage" ]))
    end

    include_examples "man-page result"

    it "body includes api_key= token" do
      expect(result.events.first[:payload]["body"]).to include("api_key=")
    end
  end

  # ── /config webhook --help ───────────────────────────────────────────────────

  describe ".call — /config webhook --help (provider key table)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/config webhook --help", args: [ "webhook" ]))
    end

    include_examples "man-page result"

    it "body includes slack= and discord= tokens" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("slack=")
      expect(body).to include("discord=")
    end
  end

  # ── /config google --help ────────────────────────────────────────────────────

  describe ".call — /config google --help (google provider with /connect hint)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/config google --help", args: [ "google" ]))
    end

    include_examples "man-page result"

    it "body includes all google key tokens" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("client_id=")
      expect(body).to include("client_secret=")
      expect(body).to include("redirect_uri=")
      expect(body).to include("api_key=")
    end

    it "body includes a /connect reference in Options" do
      expect(result.events.first[:payload]["body"]).to include("/connect")
    end
  end

  # ── /config fx --help (live showcase man page, NOT generic) ──────────────────

  describe ".call — /config fx --help (delegates to the fx showcase man page)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/config fx --help", args: [ "fx" ]))
    end

    include_examples "man-page result"

    it "is the dedicated fx man page, NOT the generic config description" do
      body = result.events.first[:payload]["body"]
      expect(body).not_to include("Read or write install-wide credentials")
      expect(body).to include("/config fx")
    end

    it "lists all three effects, each followed by a pito--fx-demo showcase row" do
      body = result.events.first[:payload]["body"]
      AppSetting::FX_EFFECTS.each do |effect|
        expect(body).to include(effect)
        expect(body).to include('data-controller="pito--fx-demo"')
        expect(body).to include(%(data-pito--fx-demo-effect-value="#{effect}"))
      end
      effects = body.scan(/data-pito--fx-demo-effect-value="(\w+)"/).flatten
      expect(effects).to eq(AppSetting::FX_EFFECTS)
    end
  end

  # ── /config motion --help (on/off man page) ──────────────────────────────────

  describe ".call — /config motion --help (delegates to the motion on/off page)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/config motion --help", args: [ "motion" ]))
    end

    include_examples "man-page result"

    it "lists the on and off states, not the generic config description" do
      body = result.events.first[:payload]["body"]
      expect(body).not_to include("Read or write install-wide credentials")
      expect(body).to include("/config motion")
      expect(body).to include(%(<span class="text-cyan">on</span>))
      expect(body).to include(%(<span class="text-cyan">off</span>))
    end
  end

  # ── /config --help (general) ─────────────────────────────────────────────────

  describe ".call — /config --help (general overview)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/config --help"))
    end

    include_examples "man-page result"

    it "body includes /config in the usage line" do
      expect(result.events.first[:payload]["body"]).to include("/config")
    end

    it "body includes a Providers: section listing all known providers" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("Providers:")
      %w[google voyage igdb webhook me sound fx].each do |p|
        expect(body).to include(p)
      end
    end
  end

  # ── /connect --help (generic command help) ───────────────────────────────────

  describe ".call — /connect --help (generic command help)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/connect --help"))
    end

    include_examples "man-page result"

    it "body includes /connect in the usage" do
      expect(result.events.first[:payload]["body"]).to include("/connect")
    end

    it "does not start OAuth — returns a simple help event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq("system")
    end
  end

  # ── /login --help ────────────────────────────────────────────────────────────

  describe ".call — /login --help" do
    it "returns Result::Ok with a man-page body containing /login" do
      result = described_class.call(invocation: build_invocation(raw: "/login --help"))
      expect(result).to be_a(Pito::Slash::Result::Ok)
      body = result.events.first[:payload]["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("/login")
    end
  end

  # ── /disconnect --help ───────────────────────────────────────────────────────

  describe ".call — /disconnect --help" do
    it "returns Result::Ok with a man-page body containing /disconnect" do
      result = described_class.call(invocation: build_invocation(raw: "/disconnect --help"))
      expect(result).to be_a(Pito::Slash::Result::Ok)
      body = result.events.first[:payload]["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("/disconnect")
    end
  end
end
