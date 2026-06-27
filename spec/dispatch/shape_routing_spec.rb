# frozen_string_literal: true

require "rails_helper"

# Phase D — shape routing: every input resolves to exactly one stack
# (:slash / :hashtag / :chat) and the harness reports the right intent. No DB.
RSpec.describe "Dispatch shape routing", type: :dispatch do
  describe "stack classification" do
    {
      "/config"        => :slash,
      "/login 123"     => :slash,
      "  /theme dim"   => :slash,   # leading whitespace tolerated
      "#a1b2 show 5"   => :hashtag,
      "  #h sync"      => :hashtag,
      "list games"     => :chat,
      "sync vids #23"  => :chat,
      "hello there"    => :chat,
      ""               => :chat,    # empty → chat (no leading sigil)
      "   "            => :chat,
      "/"              => :slash,   # lone slash still routes slash (unknown verb)
      "#"              => :hashtag  # lone hash still routes hashtag
    }.each do |input, expected_stack|
      it "routes #{input.inspect} → #{expected_stack}" do
        expect(parsed_intent(input)[:stack]).to eq(expected_stack)
      end
    end
  end

  describe "case + whitespace are not part of the sigil" do
    it "treats a leading '/' regardless of verb case" do
      expect(parsed_intent("/CONFIG")[:stack]).to eq(:slash)
    end

    it "does not treat a mid-string slash as a slash command" do
      expect(parsed_intent("list a/b")[:stack]).to eq(:chat)
    end

    it "does not treat a mid-string hash as a hashtag" do
      expect(parsed_intent("price #5 to 10")[:stack]).to eq(:chat)
    end
  end

  describe "harness sanity — verb/spec resolution wiring" do
    it "resolves a chat verb to its handler class" do
      intent = parsed_intent("sync vids #23")
      expect(intent[:verb]).to eq(:sync)
      expect(intent[:handler]).to eq(Pito::Chat::Handlers::Sync)
      expect(intent[:known]).to be(true)
    end

    it "resolves a chat alias (ls → list)" do
      intent = parsed_intent("ls games")
      expect(intent[:verb]).to eq(:list)
      expect(intent[:handler]).to eq(Pito::Chat::Handlers::List)
    end

    it "resolves a slash verb with its auth tier" do
      intent = parsed_intent("/config fx on")
      expect(intent[:verb]).to eq(:config)
      expect(intent[:auth]).to eq(:authenticated_only)
      expect(intent[:known]).to be(true)
    end

    it "resolves /login as unauthenticated-only" do
      expect(parsed_intent("/login 123")).to include(verb: :login, auth: :unauthenticated_only)
    end

    it "parses a hashtag reply into handle + action + rest" do
      expect(parsed_intent("#a1b2 sort by views desc")).to include(
        stack: :hashtag, handle: "a1b2", action: "sort", rest: "by views desc"
      )
    end

    it "flags an unknown chat verb as not known" do
      expect(parsed_intent("florp the wiggle")).to include(stack: :chat, known: false)
    end

    it "flags an unknown slash command as not known" do
      expect(parsed_intent("/bogus")).to include(stack: :slash, known: false)
    end
  end
end
