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

    context "with apostrophes in words" do
      def values(input)
        tokens(input).reject { |t| t.type == :eof }.map(&:value)
      end

      it "keeps an apostrophe-led word like \"'n\" as one :word token" do
        expect(values("Ghosts 'n Goblins")).to eq([ "Ghosts", "'n", "Goblins" ])
        expect(types("Ghosts 'n Goblins")).to eq(%i[word word word eof])
      end

      it "keeps a mid-word apostrophe (contraction) attached" do
        expect(values("don't")).to eq([ "don't" ])
      end

      it "keeps a trailing (possessive) apostrophe attached" do
        expect(values("Ghosts'")).to eq([ "Ghosts'" ])
      end

      it "handles repeated apostrophes inside a word" do
        expect(values("rock'n'roll")).to eq([ "rock'n'roll" ])
      end

      it "still marks a lone apostrophe (no following letter) as :unknown" do
        expect(types("lone ' apostrophe")).to eq(%i[word unknown word eof])
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

    describe "preceded_by_space field" do
      it "is false for the first token in the stream" do
        result = tokens("/help")
        expect(result[0].preceded_by_space).to be(false)
      end

      it "is false for tokens immediately following another token (no gap)" do
        # "/config" → slash, word — the word follows slash with no space
        result = tokens("/config")
        slash_tok = result[0]
        word_tok  = result[1]
        expect(slash_tok.preceded_by_space).to be(false)
        expect(word_tok.preceded_by_space).to be(false)
      end

      it "is true for a token that follows a whitespace run" do
        # "/config fx" → slash, word(config), word(fx)
        # "fx" is space-separated from "config"
        result = tokens("/config fx")
        expect(result[0].preceded_by_space).to be(false) # /
        expect(result[1].preceded_by_space).to be(false) # config (no space before)
        expect(result[2].preceded_by_space).to be(true)  # fx (space before)
      end

      it "is true for each space-separated token in a multi-word input" do
        result = tokens("fx on")
        expect(result[0].preceded_by_space).to be(false) # fx
        expect(result[1].preceded_by_space).to be(true)  # on
      end

      it "is false for contiguous special-char tokens (dot, colon, etc.)" do
        # "a.b.c" → word, dot, word, dot, word — no whitespace between them
        result = tokens("a.b.c")
        result.reject { |t| t.type == :eof }.each do |tok|
          expect(tok.preceded_by_space).to be(false)
        end
      end

      it "is false on the EOF token even after trailing whitespace" do
        result = tokens("hi ")
        eof_tok = result.last
        expect(eof_tok.type).to eq(:eof)
        expect(eof_tok.preceded_by_space).to be(false)
      end

      it "is false on the EOF token for whitespace-only input" do
        result = tokens("   ")
        eof_tok = result.last
        expect(eof_tok.preceded_by_space).to be(false)
      end

      # ── Whitespace edge cases ──────────────────────────────────────────────

      it "multiple consecutive spaces count as one boundary (preceded_by_space still true)" do
        # "fx   on" — three spaces between words should set preceded_by_space on "on"
        result = tokens("fx   on")
        fx_tok = result[0]
        on_tok = result[1]
        expect(fx_tok.preceded_by_space).to be(false)
        expect(on_tok.preceded_by_space).to be(true)
      end

      it "a tab character sets preceded_by_space on the following token" do
        result = tokens("fx\ton")
        expect(result[0].preceded_by_space).to be(false) # fx
        expect(result[1].preceded_by_space).to be(true)  # on (tab = whitespace)
      end

      it "NBSP (\u00A0) is NOT treated as whitespace by the lexer" do
        # Ruby /\s/ does not match U+00A0 (NBSP) — the lexer emits :unknown for it.
        # This is the documented actual behavior; callers that need to handle NBSP
        # must normalize input before lexing.
        nbsp = " "
        result = tokens("fx#{nbsp}on")
        # NBSP is emitted as :unknown, not consumed silently as whitespace
        expect(result.map(&:type)).to include(:unknown)
        # "on" is therefore NOT preceded_by_space (the :unknown was not whitespace)
        on_tok = result.find { |t| t.type == :word && t.value == "on" }
        expect(on_tok&.preceded_by_space).to be(false)
      end

      it "the last real token before :eof retains its preceded_by_space correctly (trailing space)" do
        # "hi " — word then trailing space; :eof has false; word has false
        result = tokens("hi ")
        word_tok = result.find { |t| t.type == :word }
        eof_tok  = result.last
        expect(word_tok.preceded_by_space).to be(false)
        expect(eof_tok.type).to eq(:eof)
        expect(eof_tok.preceded_by_space).to be(false)
      end

      # ── Regression guard: two space-separated words stay TWO tokens ───────
      #
      # This guards against a past bug where "/config fx on" was tokenised such that
      # "fx" and "on" were merged because preceded_by_space was lost.  The parser
      # relies on preceded_by_space to treat them as separate arguments.

      it "regression: '/config fx on' produces slash, word(config), word(fx), word(on), eof — NOT merged" do
        result = tokens("/config fx on")
        expect(result.map(&:type)).to eq(%i[slash word word word eof])
        expect(result[2].value).to eq("fx")
        expect(result[3].value).to eq("on")
        expect(result[2].preceded_by_space).to be(true)
        expect(result[3].preceded_by_space).to be(true)
      end

      it "regression: space-separated words produce distinct tokens (never merged)" do
        result = tokens("hello world")
        expect(result.map(&:type)).to eq(%i[word word eof])
        expect(result[0].value).to eq("hello")
        expect(result[1].value).to eq("world")
      end
    end

    # ── Single-token guarantee for special inputs ──────────────────────────────

    context "single-token guarantee" do
      it "a URL with port stays a single :word token" do
        result = tokens("http://localhost:3027/auth/callback")
        expect(result.first.type).to eq(:word)
        expect(result.map(&:type)).to eq(%i[word eof])
      end

      it "@handle-with-hyphen stays a single :at + :word pair (not split)" do
        # "@x-y" → :at, :word("x-y") — the word reader includes hyphens
        result = tokens("@x-y")
        expect(result.map(&:type)).to eq(%i[at word eof])
        expect(result[1].value).to eq("x-y")
      end

      it "dotted-id stays connected without spaces (a.b.c)" do
        # "a.b.c" → word, dot, word, dot, word — all contiguous (no spaces)
        result = tokens("a.b.c")
        result.reject { |t| t.type == :eof }.each do |tok|
          expect(tok.preceded_by_space).to be(false)
        end
      end

      it "a quoted string with spaces is a single :string token" do
        result = tokens('"hello world"')
        expect(result.first.type).to eq(:string)
        expect(result.first.value).to eq("hello world")
        expect(result.map(&:type)).to eq(%i[string eof])
      end
    end
  end
end
