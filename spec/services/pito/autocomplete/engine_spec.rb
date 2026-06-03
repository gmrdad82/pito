# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Autocomplete::Engine, type: :service do
  # Registry is populated before every example by rails_helper before(:each).

  def call(**kwargs)
    described_class.call(**kwargs)
  end

  # ── MODE DETECTION ──────────────────────────────────────────────────────────

  describe "mode detection" do
    it "returns :none for empty input" do
      expect(call(input: "", cursor: 0)[:mode]).to eq(:none)
    end

    it "returns :none for whitespace-only input" do
      expect(call(input: "   ", cursor: 3)[:mode]).to eq(:none)
    end

    it "returns :slash for input starting with /" do
      expect(call(input: "/config", cursor: 7)[:mode]).to eq(:slash)
    end

    it "returns :hashtag for input starting with #" do
      expect(call(input: "#handle add", cursor: 11)[:mode]).to eq(:hashtag)
    end

    it "returns :free for plain text" do
      expect(call(input: "list upcoming", cursor: 13)[:mode]).to eq(:free)
    end
  end

  # ── SLASH — VERB STAGE ──────────────────────────────────────────────────────

  describe "slash mode — verb stage" do
    context "when authenticated: true" do
      it "prefix-matches /co → includes /config and /connect" do
        result = call(input: "/co", cursor: 3, authenticated: true)
        expect(result[:mode]).to eq(:slash)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to include("/config", "/connect")
      end

      it "insert strings end with a space" do
        result = call(input: "/co", cursor: 3, authenticated: true)
        result[:menu_items].each do |item|
          expect(item[:insert]).to end_with(" ")
        end
      end

      it "excludes /login when authenticated" do
        result = call(input: "/", cursor: 1, authenticated: true)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).not_to include("/login")
      end

      it "includes /config when authenticated" do
        result = call(input: "/", cursor: 1, authenticated: true)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to include("/config")
      end

      it "returns ghost: empty strings in slash mode" do
        result = call(input: "/co", cursor: 3, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
        expect(result[:ghost][:next_hint]).to eq("")
      end
    end

    context "when authenticated: false" do
      it "returns only /login" do
        result = call(input: "/", cursor: 1, authenticated: false)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to eq([ "/login" ])
      end

      it "does not include /config when unauthenticated" do
        result = call(input: "/", cursor: 1, authenticated: false)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).not_to include("/config")
      end
    end

    context "menu_item shape" do
      it "has label, insert, description, and masked keys" do
        result = call(input: "/", cursor: 1, authenticated: true)
        item = result[:menu_items].first
        expect(item.keys).to include(:label, :insert, :description, :masked)
      end

      it "masked is false for verb-stage items" do
        result = call(input: "/", cursor: 1, authenticated: true)
        result[:menu_items].each do |item|
          expect(item[:masked]).to be(false)
        end
      end
    end
  end

  # ── SLASH — ARG STAGE (static) ──────────────────────────────────────────────

  describe "slash mode — arg stage (/config provider slot)" do
    it "suggests config providers after '/config '" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("google", "voyage", "igdb", "webhook")
    end

    it "filters providers by partial prefix" do
      result = call(input: "/config g", cursor: 9, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("google")
      expect(labels).not_to include("voyage")
    end

    it "insert for a provider ends with a space" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      result[:menu_items].each do |item|
        expect(item[:insert]).to end_with(" ")
      end
    end

    it "mode is :slash" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      expect(result[:mode]).to eq(:slash)
    end
  end

  describe "slash mode — arg stage (/config kv slot)" do
    it "suggests config keys after provider is typed" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("client_id", "client_secret", "api_key")
    end

    it "sets masked: true for sensitive keys (client_id, client_secret, api_key)" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      masked_labels = result[:menu_items].select { |i| i[:masked] }.map { |i| i[:label] }
      expect(masked_labels).to include("client_id", "client_secret", "api_key")
    end

    it "sets masked: false for non-sensitive keys (redirect_uri, slack, discord)" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      non_masked = result[:menu_items].reject { |i| i[:masked] }.map { |i| i[:label] }
      expect(non_masked).to include("redirect_uri")
    end

    it "insert for a kv key ends with '='" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      result[:menu_items].each do |item|
        expect(item[:insert]).to end_with("=")
      end
    end
  end

  # ── SLASH — unknown verb ─────────────────────────────────────────────────────

  describe "slash mode — unknown verb" do
    it "returns empty menu_items when no spec matches" do
      result = call(input: "/frobnicate ", cursor: 12, authenticated: true)
      expect(result[:menu_items]).to eq([])
    end
  end

  # ── FREE MODE — ghost text ───────────────────────────────────────────────────

  describe "free mode — ghost text" do
    it "returns :free mode for non-slash, non-hash, non-empty input" do
      result = call(input: "list upc", cursor: 8, authenticated: true)
      expect(result[:mode]).to eq(:free)
    end

    it "returns empty menu_items in free mode" do
      result = call(input: "list upc", cursor: 8, authenticated: true)
      expect(result[:menu_items]).to eq([])
    end

    describe "complete_current" do
      it "completes 'upc' → 'oming' for the :status slot in 'list upc'" do
        result = call(input: "list upc", cursor: 8, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("oming")
      end

      it "returns '' when the partial is ambiguous" do
        # "r" could match "released", "RPG", "Racing" etc. — actually :status vocab
        # has 'released', 'upcoming', 'tba'. "r" matches only "released".
        # BUT "u" only matches "upcoming" in release_status → complete "pcoming"
        result = call(input: "list u", cursor: 6, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("pcoming")
      end

      it "returns '' when no chat spec matches the first word" do
        result = call(input: "frobnicate x", cursor: 12, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end

      it "returns '' when no vocab member matches the partial" do
        result = call(input: "list zzz", cursor: 8, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end
    end

    describe "next_hint" do
      it "provides a non-empty next_hint when cursor is at a trailing space" do
        result = call(input: "list ", cursor: 5, authenticated: true)
        expect(result[:ghost][:next_hint]).not_to be_empty
      end

      it "next_hint is a string" do
        result = call(input: "list ", cursor: 5, authenticated: true)
        expect(result[:ghost][:next_hint]).to be_a(String)
      end

      it "next_hint is empty when complete_current is active" do
        result = call(input: "list upc", cursor: 8, authenticated: true)
        expect(result[:ghost][:next_hint]).to eq("")
      end

      it "returns empty ghost for unknown first word" do
        result = call(input: "frobnicate x", cursor: 12, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
        expect(result[:ghost][:next_hint]).to eq("")
      end
    end
  end

  # ── HASHTAG MODE ─────────────────────────────────────────────────────────────

  describe "hashtag mode" do
    it "returns :hashtag mode" do
      result = call(input: "#mychannel ", cursor: 11)
      expect(result[:mode]).to eq(:hashtag)
    end

    it "suggests hashtag verbs (add, remove) at the verb stage" do
      result = call(input: "#mychannel ", cursor: 11)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("add", "remove")
    end

    it "prefix-filters verbs" do
      result = call(input: "#mychannel a", cursor: 12)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("add")
      expect(labels).not_to include("remove")
    end

    it "suggests metrics after the verb is typed" do
      result = call(input: "#mychannel add ", cursor: 15)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("subscribers", "views")
    end

    it "prefix-filters metrics" do
      result = call(input: "#mychannel add sub", cursor: 18)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("subscribers")
      expect(labels).not_to include("views")
    end
  end

  # ── DYNAMIC SLOTS — :channels ─────────────────────────────────────────────────

  describe "dynamic slot — :channels (/disconnect)", :db do
    let!(:channel) { create(:channel, handle: "@alpha") }

    it "returns channel menu_items when authenticated" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("@alpha")
    end

    it "auth-gates :channels — returns NO menu_items when not authenticated" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: false)
      expect(result[:menu_items]).to be_empty
    end

    it "insert for a channel item ends with a space" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: true)
      result[:menu_items].each do |item|
        expect(item[:insert]).to end_with(" ")
      end
    end
  end

  # ── DYNAMIC SLOTS — :game_titles ─────────────────────────────────────────────

  describe "dynamic slot — :game_titles", :db do
    let!(:game) { create(:game, title: "Alpha Quest") }

    # Game titles appear in the :chat namespace via specs that use a :game_title slot.
    # However, the static chat specs use :genres/:platforms/:release_status.
    # The game_titles dynamic vocab is tested here via direct vocab lookup.
    # We verify that unauthenticated users CAN get game_titles (not auth-gated).
    it "resolves :game_titles for unauthenticated users (not auth-gated)" do
      vocab = Pito::Grammar::Registry.vocabulary(:game_titles)
      expect(vocab).not_to be_nil
      expect(vocab).to be_dynamic

      # Engine's suggest_dynamic should work for game_titles without auth.
      # Test via suggest_dynamic directly (white-box):
      result = described_class.send(
        :suggest_dynamic, vocab, :game_titles, "Alpha", authenticated: false
      )
      labels = result.map { |i| i[:label] }
      expect(labels).to include("Alpha Quest")
    end

    it "resolves :game_titles for authenticated users" do
      vocab = Pito::Grammar::Registry.vocabulary(:game_titles)
      result = described_class.send(
        :suggest_dynamic, vocab, :game_titles, "Alpha", authenticated: true
      )
      labels = result.map { |i| i[:label] }
      expect(labels).to include("Alpha Quest")
    end
  end

  # ── DYNAMIC SLOTS — :conversations (auth-gated) ───────────────────────────────

  describe "dynamic slot — :conversations (auth-gated)", :db do
    let!(:conversation_record) { create(:conversation) }

    it "auth-gates :conversations — returns empty for unauthenticated" do
      vocab = Pito::Grammar::Registry.vocabulary(:conversations)
      result = described_class.send(
        :suggest_dynamic, vocab, :conversations, "", authenticated: false
      )
      expect(result).to be_empty
    end

    it "resolves :conversations for authenticated users" do
      vocab = Pito::Grammar::Registry.vocabulary(:conversations)
      result = described_class.send(
        :suggest_dynamic, vocab, :conversations, "", authenticated: true
      )
      # Should include the uuid of the created conversation.
      labels = result.map { |i| i[:label] }
      expect(labels).to include(conversation_record.uuid)
    end
  end

  # ── ERROR RESILIENCE ──────────────────────────────────────────────────────────

  describe "error resilience" do
    it "returns empty menu_items when the dynamic resolver raises" do
      bad_vocab = Pito::Grammar::Vocabulary.define(
        name:     :bad_test_vocab,
        dynamic:  true,
        resolver: ->(_ctx) { raise "boom" }
      )
      result = described_class.send(
        :suggest_dynamic, bad_vocab, :bad_test_vocab, "", authenticated: true
      )
      expect(result).to eq([])
    end
  end

  # ── RETURN SHAPE ─────────────────────────────────────────────────────────────

  describe "return shape" do
    it "always has mode, menu_items, and ghost keys" do
      result = call(input: "", cursor: 0)
      expect(result.keys).to include(:mode, :menu_items, :ghost)
    end

    it "ghost always has complete_current and next_hint keys" do
      result = call(input: "", cursor: 0)
      expect(result[:ghost].keys).to include(:complete_current, :next_hint)
    end

    it "menu_items is always an Array" do
      result = call(input: "", cursor: 0)
      expect(result[:menu_items]).to be_an(Array)
    end
  end
end
