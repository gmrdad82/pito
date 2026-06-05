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

    describe "unquoted kwarg values with special characters" do
      it "slurps dashes and dots into a single kwarg value" do
        result = described_class.call(
          lex("/config google client_id=abc-def.ghi"),
          raw: "/config google client_id=abc-def.ghi"
        )
        expect(result.kwargs).to eq({ client_id: "abc-def.ghi" })
      end

      it "slurps a full Google client_id without quotes" do
        result = described_class.call(
          lex("/config google client_id=452280733426-sjasdasdad12123lfh6ckt4vu2.apps.googleusercontent.com"),
          raw: "/config google client_id=452280733426-sjasdasdad12123lfh6ckt4vu2.apps.googleusercontent.com"
        )
        expect(result.kwargs[:client_id]).to eq(
          "452280733426-sjasdasdad12123lfh6ckt4vu2.apps.googleusercontent.com"
        )
      end

      it "slurps a redirect URI with slashes and colons" do
        result = described_class.call(
          lex("/config google redirect_uri=http://localhost:3027/auth/youtube/callback"),
          raw: "/config google redirect_uri=http://localhost:3027/auth/youtube/callback"
        )
        expect(result.kwargs[:redirect_uri]).to eq(
          "http://localhost:3027/auth/youtube/callback"
        )
      end

      it "handles multiple kwargs where values contain special chars" do
        result = described_class.call(
          lex("/config google client_id=abc-def client_secret=xyz.123"),
          raw: "/config google client_id=abc-def client_secret=xyz.123"
        )
        expect(result.kwargs).to eq({
          client_id:     "abc-def",
          client_secret: "xyz.123"
        })
      end
    end

    describe "space-separated positional args" do
      it "produces two separate args for /config fx on" do
        result = described_class.call(lex("/config fx on"), raw: "/config fx on")
        expect(result.args).to eq(%w[fx on])
      end

      it "produces two separate args for /config sound off" do
        result = described_class.call(lex("/config sound off"), raw: "/config sound off")
        expect(result.args).to eq(%w[sound off])
      end

      it "produces three separate args when three space-separated words follow the verb" do
        result = described_class.call(lex("/cmd a b c"), raw: "/cmd a b c")
        expect(result.args).to eq(%w[a b c])
      end

      it "treats a bare /config (no args) as empty args list" do
        result = described_class.call(lex("/config"), raw: "/config")
        expect(result.args).to eq([])
      end
    end

    describe "regression: contiguous tokens still join (no space between)" do
      it "slurps a dotted id into a single arg" do
        result = described_class.call(lex("/cmd a.b.c"), raw: "/cmd a.b.c")
        expect(result.args).to eq([ "a.b.c" ])
      end

      it "slurps @handle with dash into a single arg" do
        result = described_class.call(
          lex("/disconnect @gmr-dad"),
          raw: "/disconnect @gmr-dad"
        )
        expect(result.args).to eq([ "@gmr-dad" ])
      end

      it "slurps a URL into a single kwarg value" do
        result = described_class.call(
          lex("/config google redirect_uri=http://localhost:3027/auth/callback"),
          raw: "/config google redirect_uri=http://localhost:3027/auth/callback"
        )
        expect(result.args).to eq([ "google" ])
        expect(result.kwargs[:redirect_uri]).to eq("http://localhost:3027/auth/callback")
      end

      it "keeps space-separated kwargs correctly split" do
        result = described_class.call(
          lex("/config google client_id=x redirect_uri=y"),
          raw: "/config google client_id=x redirect_uri=y"
        )
        expect(result.args).to eq([ "google" ])
        expect(result.kwargs).to eq({ client_id: "x", redirect_uri: "y" })
      end
    end

    describe "positional args with special characters" do
      it "slurps a positional arg containing dashes" do
        result = described_class.call(
          lex("/disconnect @gmrdad82-channel"),
          raw: "/disconnect @gmrdad82-channel"
        )
        expect(result.args).to eq([ "@gmrdad82-channel" ])
      end
    end

    describe "numeric kwarg values" do
      it "preserves integer type for pure digit values" do
        result = described_class.call(
          lex("/publish 42 privacy=1"),
          raw: "/publish 42 privacy=1"
        )
        expect(result.kwargs[:privacy]).to eq(1)
        expect(result.kwargs[:privacy]).to be_an(Integer)
      end

      it "preserves float type for decimal values" do
        result = described_class.call(
          lex("/set threshold=3.14"),
          raw: "/set threshold=3.14"
        )
        expect(result.kwargs[:threshold]).to eq(3.14)
        expect(result.kwargs[:threshold]).to be_a(Float)
      end
    end
  end
end
