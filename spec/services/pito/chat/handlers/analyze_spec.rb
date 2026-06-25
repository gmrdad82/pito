# frozen_string_literal: true

require "rails_helper"

# Handler for the `analyze` chat verb. On a resolvable scope it emits TWO
# pending events (:system + :enhanced) that AnalyzePrepareJob fills. Bare
# `analyze` returns the suggest copy; an unresolvable scope surfaces the
# matching error copy.
RSpec.describe Pito::Chat::Handlers::Analyze do
  def analyze(input, channel: "@all")
    msg = Pito::Chat::Parser.call(
      Pito::Lex::Lexer.call(input), raw: input, conversation: Conversation.singleton
    )
    described_class.new(message: msg, conversation: Conversation.singleton, channel:).call
  end

  def text(result)
    payload = result.events.first[:payload]
    payload[:text] || payload["text"]
  end

  it "nudges with the suggest copy for bare `analyze`" do
    expect(text(analyze("analyze"))).to include("Analyze what?")
  end

  it "surfaces the not-found error for an unknown channel handle" do
    expect(text(analyze("analyze channel @ghost"))).to include("@ghost")
  end

  it "surfaces the not-found error for unknown vid ids" do
    expect(text(analyze("analyze vids #999999"))).to include("#999999")
  end

  context "with a resolvable channel scope" do
    let!(:channel) { create(:channel, handle: "gmrdad82") }

    subject(:result) { analyze("analyze channel @gmrdad82") }

    it "returns exactly two events" do
      expect(result.events.length).to eq(2)
    end

    it "first event has kind :system" do
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "second event has kind :enhanced" do
      expect(result.events.second[:kind]).to eq(:enhanced)
    end

    it "both events have analyze.status 'pending'" do
      result.events.each do |event|
        expect(event[:payload].dig("analyze", "status")).to eq("pending")
      end
    end

    it "first event has analyze.role 'system'" do
      expect(result.events.first[:payload].dig("analyze", "role")).to eq("system")
    end

    it "second event has analyze.role 'enhanced'" do
      expect(result.events.second[:payload].dig("analyze", "role")).to eq("enhanced")
    end

    it "both events store a non-blank intro" do
      result.events.each do |event|
        expect(event[:payload].dig("analyze", "intro")).to be_a(String).and(be_present)
      end
    end

    it "both events record the channel entity id" do
      result.events.each do |event|
        expect(event[:payload].dig("analyze", "entity_ids")).to include(channel.id)
      end
    end

    it "both events record level 'channel'" do
      result.events.each do |event|
        expect(event[:payload].dig("analyze", "level")).to eq("channel")
      end
    end
  end
end
