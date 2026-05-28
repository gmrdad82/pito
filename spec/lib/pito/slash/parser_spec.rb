# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Parser do
  def lex(input)
    Pito::Lex::Lexer.call(input)
  end

  def iv(verb, args: [], kwargs: {}, raw: "")
    Pito::Slash::Invocation.new(verb:, args:, kwargs:, raw:)
  end

  describe ".call" do
    it "parses /help into verb :help with no args" do
      result = described_class.call(lex("/help"), raw: "/help")
      expect(result).to eq(iv(:help, raw: "/help"))
    end

    it "parses /publish 42 with positional number arg" do
      result = described_class.call(lex("/publish 42"), raw: "/publish 42")
      expect(result).to eq(iv(:publish, args: [ 42 ], raw: "/publish 42"))
    end

    it "parses /schedule 42 when=\"tomorrow\" with kwarg" do
      result = described_class.call(
        lex('/schedule 42 when="tomorrow"'),
        raw: '/schedule 42 when="tomorrow"'
      )
      expect(result).to eq(
        iv(:schedule, args: [ 42 ], kwargs: { when: "tomorrow" }, raw: '/schedule 42 when="tomorrow"')
      )
    end

    it "raises NotASlashCommand when input doesn't start with /" do
      expect {
        described_class.call(lex("hello"), raw: "hello")
      }.to raise_error(described_class::NotASlashCommand)
    end

    it "raises MissingVerb when / is followed by no verb" do
      expect {
        described_class.call(lex("/"), raw: "/")
      }.to raise_error(described_class::MissingVerb)
    end
  end
end
