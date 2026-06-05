# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Hashtag::Parser do
  def lex(input)
    Pito::Lex::Lexer.call(input)
  end

  describe ".call" do
    it "parses a valid handle with body tokens" do
      result = described_class.call(lex("#alpha-1234 hello world"), raw: "#alpha-1234 hello world")
      expect(result.handle).to eq(:alpha)
      expect(result.body_tokens.map(&:value)).to eq([ "hello", "world" ])
      expect(result.raw).to eq("#alpha-1234 hello world")
    end

    it "parses a valid handle with no body" do
      result = described_class.call(lex("#foo-9999"), raw: "#foo-9999")
      expect(result.handle).to eq(:foo)
      expect(result.body_tokens).to eq([])
    end

    it "raises NotAHashtag for non-hashtag input" do
      expect {
        described_class.call(lex("hello"), raw: "hello")
      }.to raise_error(described_class::NotAHashtag)
    end

    it "raises InvalidHandle when no word follows #" do
      expect {
        described_class.call(lex("#"), raw: "#")
      }.to raise_error(described_class::InvalidHandle)
    end

    it "raises InvalidHandle when token after # is not a word" do
      expect {
        described_class.call(lex("#123-456"), raw: "#123-456")
      }.to raise_error(described_class::InvalidHandle)
    end
  end
end
