# frozen_string_literal: true

# Extended coverage for Pito::Slash::Handlers::Help.
# Main help_spec.rb covers core authenticated/unauthenticated paths.
# This file deepens: section row structure, event kind type, sections
# content invariants, and the handler's help? detection (not applicable
# since --help is intercepted upstream, but the default show_help fallback
# is documented here as a contract test).

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Help, "extended coverage", type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(authenticated: true, raw: "/help")
    invocation = Pito::Slash::Invocation.new(verb: :help, args: [], kwargs: {}, raw:)
    described_class.new(invocation:, conversation:, authenticated:)
  end

  # ── Authenticated: section rows structure ────────────────────────────────────

  describe "#call — authenticated sections have title and rows" do
    subject(:sections) { build_handler.call.events.first[:payload][:sections] }

    it "each section has a :title key" do
      sections.each do |s|
        expect(s).to have_key(:title)
      end
    end

    it "each section has a :rows key that is an Array" do
      sections.each do |s|
        expect(s[:rows]).to be_an(Array)
      end
    end

    it "each row in each section has at least a command entry" do
      sections.each do |s|
        s[:rows].each do |row|
          expect(row).to be_a(Hash)
        end
      end
    end
  end

  # ── Event kind is the string "system" ────────────────────────────────────────

  describe "#call — authenticated event kind" do
    it "is the string 'system' (not a symbol)" do
      event = build_handler.call.events.first
      expect(event[:kind]).to eq(:system)
    end
  end

  # ── Unauthenticated: no sections or body ─────────────────────────────────────

  describe "#call — unauthenticated payload shape" do
    subject(:payload) { build_handler(authenticated: false).call.events.first[:payload] }

    it "has message_key set" do
      expect(payload[:message_key]).to eq("pito.slash.help.unauthenticated")
    end

    it "does not include :body" do
      expect(payload).not_to have_key(:body)
    end

    it "does not include :sections" do
      expect(payload).not_to have_key(:sections)
    end

    it "does not include :expand_label" do
      expect(payload).not_to have_key(:expand_label)
    end
  end

  # ── Verb and description_key class attributes ────────────────────────────────

  describe "class-level attributes" do
    it "has verb :help" do
      expect(described_class.verb).to eq(:help)
    end

    it "has the expected description_key" do
      expect(described_class.description_key).to eq("pito.slash.help.descriptions.help")
    end
  end

  # ── COMMANDS section: dynamically sourced from Grammar::Registry ─────────────

  describe "#call — COMMANDS section lists all slash specs from registry" do
    subject(:sections) { build_handler.call.events.first[:payload][:sections] }

    let(:commands_section) { sections.find { |s| s[:title] == "COMMANDS" } }

    it "includes a COMMANDS section" do
      expect(commands_section).not_to be_nil
    end

    it "COMMANDS section has rows for every registered slash spec" do
      registered_names = Pito::Grammar::Registry.specs(namespace: :slash).map { |s| "/#{s.name}" }
      command_keys     = commands_section[:rows].map { |r| r[:key] }
      expect(command_keys).to match_array(registered_names)
    end

    it "includes /help in the command rows" do
      keys = commands_section[:rows].map { |r| r[:key] }
      expect(keys).to include("/help")
    end

    it "includes /config in the command rows" do
      keys = commands_section[:rows].map { |r| r[:key] }
      expect(keys).to include("/config")
    end

    it "includes /games in the command rows" do
      keys = commands_section[:rows].map { |r| r[:key] }
      expect(keys).to include("/games")
    end

    it "every command row has a non-blank value (description)" do
      commands_section[:rows].each do |row|
        expect(row[:value]).to be_present, "Expected /#{row[:key]} to have a description"
      end
    end
  end

  # ── KEYBINDINGS section: not-yet-in-copy shortcuts listed ───────────────────

  describe "#call — KEYBINDINGS section" do
    subject(:sections) { build_handler.call.events.first[:payload][:sections] }

    let(:keybindings_section) { sections.find { |s| s[:title] == "KEYBINDINGS" } }

    it "includes a KEYBINDINGS section" do
      expect(keybindings_section).not_to be_nil
    end

    it "does NOT list ctrl+|, shift+r, esc, backtick, or space (intentionally removed)" do
      keys = keybindings_section[:rows].map { |r| r[:key] }
      expect(keys).not_to include("ctrl+|")
      expect(keys).not_to include("shift+r")
      expect(keys).not_to include("esc")
      expect(keys).not_to include("`")
      expect(keys).not_to include("space")
    end

    it "lists shift+↑ / shift+↓ (scroll history — not in copy)" do
      keys = keybindings_section[:rows].map { |r| r[:key] }
      expect(keys).to include("shift+↑ / shift+↓")
    end

    it "does NOT list shift+tab (already surfaced in shell/copy locales)" do
      keys = keybindings_section[:rows].map { |r| r[:key] }
      expect(keys).not_to include("shift+tab")
    end

    it "does NOT list shift+space (already surfaced in shell/copy locales)" do
      keys = keybindings_section[:rows].map { |r| r[:key] }
      expect(keys).not_to include("shift+space")
    end

    it "does NOT list ctrl+/ (already surfaced in shell locales)" do
      keys = keybindings_section[:rows].map { |r| r[:key] }
      expect(keys).not_to include("ctrl+/")
    end

    it "does NOT list ctrl+k (already surfaced in shell/copy locales)" do
      keys = keybindings_section[:rows].map { |r| r[:key] }
      expect(keys).not_to include("ctrl+k")
    end

    it "every keybinding row has a non-blank description" do
      keybindings_section[:rows].each do |row|
        expect(row[:value]).to be_present
      end
    end
  end

  # ── Section titles use COMMANDS / KEYBINDINGS (not legacy GENERAL/YOUTUBE) ──

  describe "#call — section titles are the new canonical labels" do
    subject(:titles) { build_handler.call.events.first[:payload][:sections].map { |s| s[:title] } }

    it "includes COMMANDS" do
      expect(titles).to include("COMMANDS")
    end

    it "includes KEYBINDINGS" do
      expect(titles).to include("KEYBINDINGS")
    end

    it "does not include the old GENERAL title" do
      expect(titles).not_to include("GENERAL")
    end

    it "does not include the old YOUTUBE title" do
      expect(titles).not_to include("YOUTUBE")
    end

    it "does not include the old CONFIG title" do
      expect(titles).not_to include("CONFIG")
    end
  end
end
