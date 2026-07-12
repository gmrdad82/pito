# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `greet` (recognition only, DB mocked) ─────────────────────
#
# RULE: every greeting phrase that should be recognized IS recognized — no exception.
#
# Recognition engine: Pito::Chat::Parser (lib/pito/chat/parser.rb)
#   GREETINGS = Set.new([...23 phrases...]).freeze
#   normalized_phrase = raw.strip.downcase.gsub(/[[:punct:]]+\z/, "").strip.gsub(/\s+/, " ")
#   match = GREETINGS.include?(normalized_phrase)
#
# This path is DB-free: conversation is stored but never accessed for greetings;
# tokens are inspected only AFTER the greeting short-circuit. We pass [] tokens and
# nil conversation — both are safe and keep this suite at zero factories.
#
# Positive: all 23 canonical phrases + case / punctuation / whitespace variants
# Negative: greeting-prefix phrases with trailing words, known commands, random text

RSpec.describe "Dispatch matrix — greet (recognition, DB mocked)", type: :dispatch do
  # Direct entry point: Parser with empty token list + nil conversation.
  # Greeting detection reads only @raw — tokens and conversation are never touched.
  def parse(raw)
    Pito::Chat::Parser.call([], raw: raw, conversation: nil)
  end

  def greet?(raw)
    parse(raw).tool == :greet
  end

  # ── all 23 canonical phrases (verbatim from GREETINGS) ───────────────────────
  describe "canonical phrases (verbatim) → :greet" do
    [
      "hi", "hii", "hiya",
      "hey", "heya",
      "hello", "helloo",
      "hello there", "hey there", "hi there",
      "hola",
      "yo",
      "sup",
      "howdy",
      "greetings",
      "good morning", "good afternoon", "good evening",
      "morning", "evening",
      "whats up", "what's up",
      "wassup"
    ].each do |phrase|
      it "#{phrase.inspect} → :greet" do
        expect(greet?(phrase)).to be true
      end
    end
  end

  # ── case-insensitive variants ─────────────────────────────────────────────────
  describe "uppercase/mixed-case variants → :greet" do
    {
      "Hi"              => "hi",
      "HI"              => "hi",
      "Hii"             => "hii",
      "Hiya"            => "hiya",
      "HIYA"            => "hiya",
      "Hey"             => "hey",
      "HEY"             => "hey",
      "Heya"            => "heya",
      "Hello"           => "hello",
      "HELLO"           => "hello",
      "Helloo"          => "helloo",
      "Hello There"     => "hello there",
      "HELLO THERE"     => "hello there",
      "Hey There"       => "hey there",
      "HEY THERE"       => "hey there",
      "Hi There"        => "hi there",
      "HI THERE"        => "hi there",
      "Hola"            => "hola",
      "HOLA"            => "hola",
      "Yo"              => "yo",
      "YO"              => "yo",
      "Sup"             => "sup",
      "SUP"             => "sup",
      "Howdy"           => "howdy",
      "HOWDY"           => "howdy",
      "Greetings"       => "greetings",
      "GREETINGS"       => "greetings",
      "Good Morning"    => "good morning",
      "GOOD MORNING"    => "good morning",
      "Good Afternoon"  => "good afternoon",
      "GOOD AFTERNOON"  => "good afternoon",
      "Good Evening"    => "good evening",
      "GOOD EVENING"    => "good evening",
      "Morning"         => "morning",
      "MORNING"         => "morning",
      "Evening"         => "evening",
      "EVENING"         => "evening",
      "Whats Up"        => "whats up",
      "WHATS UP"        => "whats up",
      "What's Up"       => "what's up",
      "WHAT'S UP"       => "what's up",
      "Wassup"          => "wassup",
      "WASSUP"          => "wassup"
    }.each do |input, _canonical|
      it "#{input.inspect} → :greet" do
        expect(greet?(input)).to be true
      end
    end
  end

  # ── trailing punctuation stripped (gsub /[[:punct:]]+\z/) ────────────────────
  describe "trailing punctuation variants → :greet" do
    [
      "hi!", "hi.", "hi?", "hi...", "hi!?",
      "hii!", "hiya!",
      "hey!", "hey?", "hey.",
      "heya!",
      "hello!", "hello.", "hello?",
      "helloo!",
      "hello there!", "hey there!", "hi there!",
      "hola!", "hola.",
      "yo!", "yo?",
      "sup?", "sup!",
      "howdy!", "howdy?",
      "greetings!", "greetings.",
      "good morning!", "good morning.",
      "good afternoon!",
      "good evening!",
      "morning!", "evening!",
      "whats up?", "whats up!",
      "what's up?", "what's up!",
      "wassup!"
    ].each do |input|
      it "#{input.inspect} → :greet" do
        expect(greet?(input)).to be true
      end
    end
  end

  # ── leading / trailing whitespace stripped ────────────────────────────────────
  describe "surrounding-whitespace variants → :greet" do
    [
      " hi",
      "hi ",
      "  hi  ",
      "\thi\t",
      " hello",
      "hello ",
      "  hello  ",
      "\thello\t",
      " hey ",
      " yo ",
      " hola ",
      " howdy ",
      " greetings ",
      " good morning ",
      " morning ",
      " evening "
    ].each do |input|
      it "#{input.inspect} → :greet" do
        expect(greet?(input)).to be true
      end
    end
  end

  # ── inner whitespace collapsed (gsub /\s+/, " ") ─────────────────────────────
  describe "inner-whitespace collapsed variants → :greet" do
    [
      "hello  there",
      "hey  there",
      "hi  there",
      "good  morning",
      "good  afternoon",
      "good  evening",
      "whats  up",
      "what's  up"
    ].each do |input|
      it "#{input.inspect} → :greet" do
        expect(greet?(input)).to be true
      end
    end
  end

  # ── combined normalization (case + punctuation + whitespace) ──────────────────
  describe "fully-combined normalization variants → :greet" do
    [
      "  Hi!  ",
      "  HELLO!  ",
      "  Hey?  ",
      "\tHEY\t",
      "  Hola!  ",
      "  Yo!  ",
      " SUP? ",
      "  Howdy!  ",
      "  Greetings!  ",
      "  Hiya!  ",
      " Good Morning! ",
      " GOOD MORNING! ",
      "  Good  Morning!  ",
      " Good Afternoon! ",
      " Good Evening! ",
      " WHAT'S UP? ",
      " Whats  Up? ",
      "  Wassup!  "
    ].each do |input|
      it "#{input.inspect} → :greet" do
        expect(greet?(input)).to be true
      end
    end
  end

  # ── NOT greetings ─────────────────────────────────────────────────────────────
  #
  # Matching is whole-phrase: "hello world" ≠ "hello", "hi how are you" ≠ "hi".
  # Known commands, NL sentences, and prefixed-greeting phrases all fall through.
  describe "non-greetings → not :greet" do
    # greeting token followed by more words (whole-phrase match fails)
    [
      "hello world",
      "hello there friend",
      "hi how are you",
      "hi there buddy",
      "hey you",
      "hey list games",
      "yo what's up",
      "good morning everyone",
      "good morning sunshine",
      "what's up dude",
      "saying hi",
      "just saying hi",

      # known chat commands
      "list games",
      "show videos",
      "help",
      "analyze channel",
      "import",
      "find zelda",
      "delete game",
      "stats",

      # random / unparseable
      "boo!",
      "random text",
      "xyzzy frobble",
      "I'm hungry",
      "not a greeting",
      "12345",
      ""
    ].each do |input|
      it "#{input.inspect} → not :greet" do
        expect(greet?(input)).to be false
      end
    end
  end
end
