# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Rename, type: :service do
  let(:conversation) { Conversation.create!(title: "Untitled") }

  def build_handler(raw)
    invocation = Pito::Slash::Invocation.new(verb: :rename, args: raw.split.drop(1), kwargs: {}, raw: raw)
    described_class.new(invocation:, conversation:)
  end

  it "is registered in the slash registry as :rename" do
    expect(Pito::Slash::Registry.lookup(:rename)).to eq(described_class)
    expect(described_class.verb).to eq(:rename)
  end

  describe "#call — /rename <title>" do
    it "renames the current conversation" do
      build_handler("/rename Strategy Channel").call
      expect(conversation.reload.title).to eq("Strategy Channel")
    end

    it "preserves spaces in a multi-word title" do
      build_handler("/rename My Long Strategy Name").call
      expect(conversation.reload.title).to eq("My Long Strategy Name")
    end

    it "returns an Ok :system confirmation naming the new title" do
      result = build_handler("/rename Strategist").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq("system")
      expect(event[:payload]["text"]).to include("Strategist")
    end
  end

  describe "#call — bare /rename (no title)" do
    subject(:result) { build_handler("/rename").call }

    it "does NOT rename (no blank titles)" do
      result
      expect(conversation.reload.title).to eq("Untitled")
    end

    it "returns a usage hint" do
      expect(result.events.first[:payload][:text]).to include("/rename")
    end
  end

  describe "#call — /rename --help" do
    subject(:result) { build_handler("/rename --help").call }

    it "renders a man-style help body (html), not a rename" do
      expect(result.events.first[:payload]["html"]).to be(true)
      expect(result.events.first[:payload]["body"]).to include("/rename")
      expect(conversation.reload.title).to eq("Untitled")
    end
  end
end
