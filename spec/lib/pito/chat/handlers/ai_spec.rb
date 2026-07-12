# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Ai do
  let(:conversation) { Conversation.singleton }

  def dispatch(raw)
    msg = Pito::Chat::Parser.call(Pito::Lex::Lexer.call(raw), raw:, conversation:)
    described_class.new(message: msg, conversation:).call
  end

  it "emits ONE pending :ai event carrying the raw prompt" do
    result = dispatch("@ai what should I play next?")

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.size).to eq(1)
    event = result.events.first
    expect(event[:kind]).to eq(:ai)
    expect(event[:payload]).to eq(
      "status" => "pending", "blocks" => [], "prompt" => "what should I play next?"
    )
  end

  it "keeps the prompt raw — fillers and casing untouched" do
    result = dispatch("@Ai please show me the BEST game, ordered by vibes")

    expect(result.events.first[:payload]["prompt"])
      .to eq("please show me the BEST game, ordered by vibes")
  end

  it "asks for a prompt on bare `ai`" do
    result = dispatch("ai")

    expect(result.events.first[:kind]).to eq(:system)
    expect(result.events.first[:payload]["text"]).to include("Ask me something")
  end

  it "opts the message into web tools on --web, stripping the flag from the prompt" do
    result = dispatch("@ai --web what is new")

    payload = result.events.first[:payload]
    expect(payload["web"]).to be(true)
    expect(payload["prompt"]).to eq("what is new")
  end

  it "carries no web key without the flag" do
    result = dispatch("@ai what is new")

    expect(result.events.first[:payload]).not_to have_key("web")
  end

  it "asks for a prompt on `@ai --web` — the flag alone is not a prompt" do
    result = dispatch("@ai --web")

    expect(result.events.first[:kind]).to eq(:system)
    expect(result.events.first[:payload]["text"]).to include("Ask me something")
  end
end
