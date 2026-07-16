# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::HelpBuilder do
  def build_invocation(raw:, args: [])
    tool = raw.strip.split(/\s+/).first.delete_prefix("/").to_sym
    Pito::Slash::Invocation.new(tool:, args:, kwargs: {}, raw:)
  end

  # Every --help response must be a man-page block.
  shared_examples "man-page result" do
    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns exactly 1 system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
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

  # ── /config --help (general) ─────────────────────────────────────────────────

  describe ".call — /config --help (general overview)" do
    subject(:result) do
      described_class.call(invocation: build_invocation(raw: "/config --help"))
    end

    include_examples "man-page result"

    it "body includes /config in the usage line" do
      expect(result.events.first[:payload]["body"]).to include("/config")
    end

    it "body groups providers under the three titled sections (T16.3: AI / Sources / Profile)" do
      body = result.events.first[:payload]["body"]
      [ "AI:", "Sources:", "Profile:" ].each do |title|
        expect(body).to include(title)
      end
      expect(body).not_to include("Providers:")
    end

    it "body lists every known provider with its description line" do
      body = result.events.first[:payload]["body"]
      %w[ai tavily google igdb webhook sound timezone].each do |p|
        expect(body).to include(p)
        expect(body).to include(
          ERB::Util.html_escape(I18n.t("pito.slash.config.help.general.providers.#{p}"))
        )
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
      expect(result.events.first[:kind]).to eq(:system)
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

  # ── Handlers that override #show_help now render their RICH page via the
  #    dispatcher path (previously dead — the dispatcher rendered generic help).
  #    These drive the real HelpBuilder.call, closing that coverage gap.

  describe ".call — /games --help (rich Subcommands page, not generic)" do
    subject(:result) { described_class.call(invocation: build_invocation(raw: "/games --help")) }

    include_examples "man-page result"

    it "renders the import subcommand section, not the bare generic page" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("Subcommands")
      expect(body).to include("import")
    end
  end

  describe ".call — /jobs --help (rich Subcommands page)" do
    subject(:result) { described_class.call(invocation: build_invocation(raw: "/jobs --help")) }

    include_examples "man-page result"

    it "renders the subcommands section" do
      expect(result.events.first[:payload]["body"]).to include("Subcommands")
    end
  end

  describe ".call — /rename --help (rich Arguments page)" do
    subject(:result) { described_class.call(invocation: build_invocation(raw: "/rename --help")) }

    include_examples "man-page result"

    it "renders the arguments section with the new-title argument" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("Arguments")
      expect(body).to include("new title")
    end
  end
end
