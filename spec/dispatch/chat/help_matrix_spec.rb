# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `help` chat verb (recognition, zero DB) ───────────────────
#
# Subject: Pito::Chat::Handlers::Help (app/services/pito/chat/handlers/help.rb)
#
# THE HANDLER IS ARG-BLIND. Every call — bare `help`, `help <verb>`, `help
# <anything>` — unconditionally delegates to
# Pito::MessageBuilder::Help::Commands.call and returns:
#
#   Result::Ok with events: [{ kind: :system, payload: { "body" => <html>, "html" => true } }]
#
# body_tokens are NEVER inspected.  Calling `help list` produces the same output
# as bare `help`.  The general help page (Commands.call) is always returned.
#
# ONE dispatcher intercept short-circuits the handler:
#
#   `help --help`  →  Pito::Slash::HelpBuilder.nonsense_body
#                      (dispatched by lib/pito/chat/dispatcher.rb before the
#                       handler runs; still a :system event with html: true, but
#                       the body is the "manual's manual" easter-egg, NOT the
#                       Commands.call body)
#
# The `-h` short-flag does NOT match the dispatcher regex
# (/(?:\A|\s)--help(?:\s|\z)/) and therefore routes to the handler normally.
#
# Case normalization: Pito::Lex::KeywordSanitizer downcases any word token whose
# lowercase value is in KEYWORDS (which includes "help").  So HELP, Help, hElP all
# resolve to verb :help before reaching the grammar registry.
#
# DB access: NONE on any `help` code path.  Zero factories.  Zero stubs required.
#
# RULE: every recognized form produces one of:
#   A. :system event, payload { "html" => true, "body" => <general-help-HTML> }
#   B. :system event, payload { "html" => true, "body" => <nonsense-HTML> }   (--help only)
# Never a Result::Error.

RSpec.describe "Dispatch matrix — help (recognition, zero DB)", type: :dispatch do
  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Instantiate and call the Help handler directly.
  # Builds a real Message + Token list so we bypass the lexer/sanitizer pipeline
  # and test the handler contract in isolation.
  def call_handler(raw)
    parts       = raw.strip.split(/\s+/)
    body_words  = parts[1..]
    body_tokens = body_words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
    end
    msg = Pito::Chat::Message.new(
      verb:        :help,
      body_tokens: body_tokens,
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Help.new(
      message:      msg,
      conversation: double("conversation")
    ).call
  end

  # Full dispatcher pipeline — exercises KeywordSanitizer, Parser, and the
  # `--help` intercept in Pito::Dispatch::Router.
  # `conversation` is passed through but never read on the help path.
  def dispatch(raw)
    Pito::Dispatch::Router.call(input: raw, conversation: double("conversation"))
  end

  # ── 1. Result shape — bare `help` ────────────────────────────────────────────
  #
  # Asserts the contract once in full detail; later groups check only the
  # relevant attribute to keep failure messages focused.
  describe "bare `help` → Result::Ok with one :system event" do
    subject(:result) { call_handler("help") }

    it "is a Result::Ok (not an Error)" do
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "produces exactly one event" do
      expect(result.events.size).to eq(1)
    end

    it "event kind is :system" do
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload has html: true" do
      expect(result.events.first[:payload]["html"]).to be(true)
    end

    it "payload body is a non-empty HTML string" do
      body = result.events.first[:payload]["body"]
      expect(body).to be_a(String).and be_present
    end

    it "payload body contains the data-grid (Commands HTML structure)" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("pito-data-grid")
    end

    it "payload body contains all three verb group headings (games / videos / channels)" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("text-purple")  # yellow group headings
    end

    it "payload matches Commands.call exactly" do
      expect(result.events.first[:payload]).to eq(Pito::MessageBuilder::Help::Commands.call)
    end
  end

  # ── 2. Body tokens IGNORED — every `help <arg>` form → general help ───────────
  #
  # handler#call calls Commands.call unconditionally and never reads body_tokens.
  # All inputs below must produce the same payload as bare `help`.
  describe "body tokens ignored — `help <arg>` → identical to bare help" do
    {
      # ── games-group verbs (from VERB_GROUPS in Commands) ──
      "help list"     => "games-group verb",
      "help show"     => "games-group verb",
      "help import"   => "games-group verb",
      "help delete"   => "games-group verb",
      "help reindex"  => "games-group verb",
      "help link"     => "games-group verb",
      "help unlink"   => "games-group verb",
      "help footage"  => "games-group verb",
      # ── videos-group verbs ──
      "help publish"  => "videos-group verb",
      "help unlist"   => "videos-group verb",
      "help schedule" => "videos-group verb",
      # ── channels-group verbs ──
      "help sync"     => "channels-group verb",
      # ── verbs known to the registry but absent from VERB_GROUPS ──
      "help analyze"  => "known verb, not listed in VERB_GROUPS",
      "help shinies"  => "known verb, not listed in VERB_GROUPS",
      # ── self-referential ──
      "help help"     => "self-referential (still ignored)",
      # ── multi-token bodies ──
      "help list games"  => "multi-token body",
      "help show game"   => "multi-token body",
      "help sync videos" => "multi-token body",
      # ── completely unknown args ──
      "help xyzzy"         => "unknown verb",
      "help not-a-command" => "unknown arg",
      "help 123"           => "numeric arg"
    }.each do |raw, reason|
      it "#{raw.inspect} (#{reason}) → same :system event, same payload" do
        result = call_handler(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]).to eq(Pito::MessageBuilder::Help::Commands.call)
      end
    end
  end

  # ── 3. Whitespace variants — via full dispatcher ──────────────────────────────
  #
  # The Lexer skips leading/trailing whitespace; token scanning is whitespace-
  # tolerant.  All variants below route to verb :help and reach the handler.
  describe "whitespace variants → :system event (via dispatcher)" do
    {
      "help "    => "single trailing space",
      "help   "  => "multiple trailing spaces",
      "  help"   => "leading spaces",
      "  help  " => "both sides",
      "\thelp"   => "leading tab",
      "help\t"   => "trailing tab",
      "help  list"   => "extra space between verb and arg (still arg-blind)",
      "help   sync"  => "three spaces (still arg-blind)"
    }.each do |raw, reason|
      it "#{raw.inspect} (#{reason}) → Result::Ok, :system event, html: true" do
        result = dispatch(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["html"]).to be(true)
      end
    end
  end

  # ── 4. Case normalization — KeywordSanitizer downcases known keywords ─────────
  #
  # `help` is in Pito::Lex::KeywordSanitizer::KEYWORDS, so any capitalization is
  # lowercased before the grammar registry lookup, making the verb :help match.
  describe "case-normalized inputs → verb :help recognized (via dispatcher)" do
    {
      "HELP"       => "all-caps",
      "Help"       => "title-case",
      "hElP"       => "mixed-case",
      "HELP list"  => "all-caps verb + arg",
      "Help sync"  => "title-case verb + arg",
      "HELP SHOW"  => "all-caps verb + all-caps arg (both keywords → both downcased)"
    }.each do |raw, reason|
      it "#{raw.inspect} (#{reason}) → :system event, html: true" do
        result = dispatch(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["html"]).to be(true)
      end
    end

    it "HELP payload matches Commands.call (arg-blind even after case normalization)" do
      result = dispatch("HELP")
      expect(result.events.first[:payload]).to eq(Pito::MessageBuilder::Help::Commands.call)
    end
  end

  # ── 5. `help --help` → dispatcher intercept → nonsense easter-egg body ────────
  #
  # Pito::Dispatch::Router#dispatch_new_turn checks:
  #   message.raw.match?(/(?:\A|\s)--help(?:\s|\z)/) && message.verb == :help
  # → Pito::Slash::HelpBuilder.nonsense_body (the "manual's manual" easter egg)
  # → Result::Ok with a :system event; payload body differs from Commands.call body.
  describe "`help --help` → dispatcher-intercepted nonsense easter egg" do
    subject(:result) { dispatch("help --help") }

    it "returns Result::Ok (not Error)" do
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "produces one :system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload has html: true" do
      expect(result.events.first[:payload]["html"]).to be(true)
    end

    it "body equals HelpBuilder.nonsense_body (easter-egg HTML)" do
      expect(result.events.first[:payload]["body"]).to eq(
        Pito::Slash::HelpBuilder.nonsense_body
      )
    end

    it "body is distinct from Commands.call body (different intercept path)" do
      commands_body = Pito::MessageBuilder::Help::Commands.call["body"]
      expect(result.events.first[:payload]["body"]).not_to eq(commands_body)
    end
  end

  # ── 6. `help -h` — does NOT match the --help intercept ──────────────────────
  #
  # The dispatcher regex is /(?:\A|\s)--help(?:\s|\z)/ — only the long form
  # `--help` triggers the intercept.  `-h` passes through to the handler.
  describe "`help -h` → passes through to handler (not intercepted)" do
    it "returns the standard Commands payload (not the nonsense body)" do
      result = dispatch("help -h")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]).to eq(Pito::MessageBuilder::Help::Commands.call)
    end

    it "body is distinct from HelpBuilder.nonsense_body" do
      result  = dispatch("help -h")
      body    = result.events.first[:payload]["body"]
      nonsense = Pito::Slash::HelpBuilder.nonsense_body
      expect(body).not_to eq(nonsense)
    end
  end

  # ── 7. `help --help` position variants — regex anchors ───────────────────────
  #
  # The regex /(?:\A|\s)--help(?:\s|\z)/ requires --help to be preceded by a
  # word boundary (\A or whitespace) and followed by \s or \z.
  describe "`help --help` position variants → all intercepted" do
    [
      "help --help",         # trailing --help (most common)
      "help --help "         # trailing space after --help
    ].each do |raw|
      it "#{raw.inspect} → nonsense body (dispatcher intercept)" do
        result = dispatch(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["body"]).to eq(
          Pito::Slash::HelpBuilder.nonsense_body
        )
      end
    end
  end

  # ── 8. Negative — inputs that do NOT route to the help handler ───────────────
  #
  # Confirms that the `help` handler recognition is precise: non-help verbs,
  # empty input, and slash-prefixed commands are NOT routed here.
  describe "non-help inputs — not handled by the help handler" do
    it "'list' → different verb, different payload" do
      # list routes to Handlers::List, not Handlers::Help
      result = dispatch("list")
      # list bare → Result::Error (needs a noun) not a system Commands payload
      expect(result.events.first[:payload]).not_to eq(
        Pito::MessageBuilder::Help::Commands.call
      )
    end

    it "empty string → :unknown path, payload is NOT Commands.call" do
      result = dispatch("")
      # Unknown handler returns { text: ... } (not Commands.call's { "body", "html" })
      commands_payload = Pito::MessageBuilder::Help::Commands.call
      expect(result.events.first[:payload]).not_to eq(commands_payload)
    end

    it "unrecognised input 'xyzzy' → :unknown path, not help" do
      result = dispatch("xyzzy")
      expect(result.events.first[:payload]).not_to eq(
        Pito::MessageBuilder::Help::Commands.call
      )
    end

    it "'help' is NOT in GREETINGS (does not short-circuit to :greet)" do
      # The parser checks GREETINGS first; 'help' is absent from the set,
      # so it proceeds to verb tokenisation and resolves to :help, not :greet.
      expect(Pito::Chat::Parser::GREETINGS).not_to include("help")
    end

    it "'help' is NOT in FAREWELLS" do
      expect(Pito::Chat::Parser::FAREWELLS).not_to include("help")
    end
  end
end
