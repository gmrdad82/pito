# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Lex::Lexer do
  def tokens(input)
    described_class.call(input)
  end

  def t(type, value, position)
    Pito::Lex::Token.new(type:, value:, position:)
  end

  # Helper: extract just the types from a token array for quick assertions
  def types(input)
    tokens(input).map(&:type)
  end

  describe ".call" do
    context "with an empty string" do
      it "returns only EOF" do
        expect(tokens("")).to eq([ t(:eof, "", 0) ])
      end
    end

    context "with whitespace-only input" do
      it "returns only EOF" do
        expect(tokens("   \t  ")).to eq([ t(:eof, "", 6) ])
      end
    end

    context "with /help" do
      it "produces slash, word, eof" do
        expect(types("/help")).to eq(%i[slash word eof])
      end

      it "has correct positions" do
        result = tokens("/help")
        expect(result[0].position).to eq(0) # /
        expect(result[1].position).to eq(1) # help
      end

      it "has correct values" do
        result = tokens("/help")
        expect(result[0].value).to eq("/")
        expect(result[1].value).to eq("help")
      end
    end

    context "with :slash token" do
      it "recognizes a bare /" do
        expect(types("/")).to eq(%i[slash eof])
      end
    end

    context "with :colon token" do
      it "recognizes :" do
        expect(types(":")).to eq(%i[colon eof])
      end
    end

    context "with :equals token" do
      it "recognizes =" do
        expect(types("=")).to eq(%i[equals eof])
      end
    end

    context "with :comma token" do
      it "recognizes ," do
        expect(types(",")).to eq(%i[comma eof])
      end
    end

    context "with :at token" do
      it "recognizes @" do
        expect(types("@")).to eq(%i[at eof])
      end
    end

    context "with :dot token" do
      it "recognizes ." do
        expect(types(".")).to eq(%i[dot eof])
      end
    end

    context "with :number token" do
      it "tokenizes a single digit" do
        expect(tokens("7")).to eq([ t(:number, "7", 0), t(:eof, "", 1) ])
      end

      it "tokenizes a multi-digit number" do
        expect(tokens("42")).to eq([ t(:number, "42", 0), t(:eof, "", 2) ])
      end
    end

    context "with :word token" do
      it "tokenizes a simple word" do
        expect(tokens("hello")).to eq([ t(:word, "hello", 0), t(:eof, "", 5) ])
      end

      it "tokenizes words with underscores and hyphens" do
        expect(types("my_var test-slug")).to eq(%i[word word eof])
      end
    end

    context "with :string token" do
      it "tokenizes a double-quoted string" do
        result = tokens('"hello"')
        expect(result[0].type).to eq(:string)
        expect(result[0].value).to eq("hello")
      end

      it "handles escaped quotes inside the string" do
        result = tokens('"say \"hi\" please"')
        expect(result[0].type).to eq(:string)
        expect(result[0].value).to eq('say "hi" please')
      end

      it "tracks position of the opening quote" do
        result = tokens('  "hi"')
        expect(result[0].position).to eq(2)
      end
    end

    context "with :unknown token" do
      it "marks unrecognized characters as unknown" do
        expect(types("~")).to eq(%i[unknown eof])
      end

      it "skips whitespace around unknowns" do
        expect(types(" ~ ")).to eq(%i[unknown eof])
      end
    end

    context "with URL values" do
      it "tokenizes a bare http URL as a single word token" do
        result = tokens("http://localhost:3027/auth/youtube/callback")
        expect(result.map(&:type)).to eq(%i[word eof])
        expect(result.first.value).to eq("http://localhost:3027/auth/youtube/callback")
      end

      it "tokenizes https URLs as a single word token" do
        result = tokens("https://example.com/path?foo=1&bar=2")
        expect(result.map(&:type)).to eq(%i[word eof])
        expect(result.first.value).to eq("https://example.com/path?foo=1&bar=2")
      end

      it "tokenizes kwarg=URL as word equals word (not split on the port colon)" do
        result = tokens("redirect_uri=http://localhost:3027/auth/callback")
        expect(result.map(&:type)).to eq(%i[word equals word eof])
        expect(result[2].value).to eq("http://localhost:3027/auth/callback")
      end

      it "does not swallow the next kwarg after a URL" do
        result = tokens("redirect_uri=http://localhost:3027/cb client_id=abc")
        types_arr = result.map(&:type)
        expect(types_arr).to eq(%i[word equals word word equals word eof])
        expect(result[2].value).to eq("http://localhost:3027/cb")
        expect(result[3].value).to eq("client_id")
      end
    end

    context "with a realistic slash command" do
      it "tokenizes /schedule 42 for \"tomorrow at noon\"" do
        result = tokens('/schedule 42 for "tomorrow at noon"')
        expect(result.map(&:type)).to eq(%i[slash word number word string eof])
        expect(result.map(&:value)).to eq([ "/", "schedule", "42", "for", "tomorrow at noon", "" ])
      end

      it "tokenizes /publish key=value" do
        result = tokens("/publish key=value")
        expect(result.map(&:type)).to eq(%i[slash word word equals word eof])
      end
    end

    context "with position offsets" do
      it "reports correct positions after whitespace" do
        result = tokens("  /help")
        expect(result[0].position).to eq(2) # slash at column 2
        expect(result[1].position).to eq(3) # help at column 3
      end
    end
  end
end
