# frozen_string_literal: true

require "rails_helper"

# Conversational greetings / farewells (phrase-matched in Pito::Chat::Parser) and
# the witty :system reply for from-the-start-unparseable input.
RSpec.describe "Chat greetings, farewells & the witty unknown reply" do
  let(:conversation) { Conversation.singleton }

  def reply(input)
    Pito::Dispatch::Router.call(input:, conversation:)
  end

  def system_text(result)
    expect(result).to be_a(Pito::Chat::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq(:system)
    event[:payload][:text]
  end

  describe "greetings → a witty hello (case-insensitive, single & multi-word)" do
    %w[hi Hi HELLO Hola hey yo yo!].each do |input|
      it "treats #{input.inspect} as a greeting" do
        expect(system_text(reply(input))).to be_present
      end
    end

    it "matches multi-word greetings like 'good morning'" do
      expect(system_text(reply("Good morning"))).to be_present
    end
  end

  describe "farewells → a witty goodbye (incl. punctuation & multi-word)" do
    [ "bye", "Bye!", "goodbye", "good bye", "hasta luego", "see'ya", "ciao", "later" ].each do |input|
      it "treats #{input.inspect} as a farewell" do
        expect(system_text(reply(input))).to be_present
      end
    end
  end

  describe "from-the-start-unparseable input → witty :system reply (NOT an error)" do
    [ "boo!", "I'm hungry", "xyzzy frobble" ].each do |input|
      it "replies wittily (and points to help) for #{input.inspect}" do
        expect(system_text(reply(input)).downcase).to include("help")
      end
    end
  end
end
