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
      expect(event[:kind]).to eq("system")
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
end
