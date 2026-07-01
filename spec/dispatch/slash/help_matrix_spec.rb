# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/help` (recognition only, zero DB) ─────────────────────
#
# RULE: every kwarg combination recognised — no exception.
#
# `/help` has NO slots, NO aliases, and NO kwargs. The sole recognised
# dimension is the `authenticated` flag, which controls whether the handler
# returns the full sectioned help page or the unauthenticated login instruction.
# All other dispatch paths are Dispatcher-level (--help intercept, arity guard).
#
# ── What is mocked ──────────────────────────────────────────────────────────
#   Nothing. The handler reads only I18n and Pito::Grammar::Registry (both
#   in-memory); the Dispatcher reads only I18n and the lexer (pure). Zero DB.
#
# ── What is NOT mocked ───────────────────────────────────────────────────────
# • I18n (uses real locale files — spec fails fast if a copy key is missing)
# • Pito::Copy.render (real — uses I18n + in-memory sampler)
# • Pito::Grammar::Registry (in-memory, no DB)
# • Pito::Slash::HelpBuilder (real — produces the nonsense man-page HTML)
# • Pito::MessageBuilder::ManPage (real — produces .pito-help-block HTML)
#
# ── Auth gate ────────────────────────────────────────────────────────────────
# Grammar declares `auth :any` — the Dispatcher does NOT gate on auth before
# calling the handler. The handler itself branches: full_help (authenticated)
# vs restricted_help (unauthenticated). There is NO ChatDispatchJob gate on
# top of this because `/help` uses `auth :any`.
#
# ── No RECOGNITION BUGS found ────────────────────────────────────────────────
# All documented forms behave exactly as the handler and dispatcher describe.
RSpec.describe "Dispatch matrix — /help (recognition, zero DB)", type: :dispatch do
  # Build a handler directly — bypasses the Dispatcher's arity guard and
  # --help intercept so we can assert the handler's own auth-branching logic.
  # The handler never uses `conversation` in any path, so nil is safe.
  def build_handler(raw: "/help", authenticated: true)
    invocation = Pito::Slash::Invocation.new(verb: :help, args: [], kwargs: {}, raw:)
    Pito::Slash::Handlers::Help.new(invocation:, conversation: nil, authenticated:)
  end

  # Thin wrapper for going through the real Dispatcher (arity guard + --help).
  # conversation: nil — the Help handler never touches it.
  def dispatch(raw, authenticated: true)
    Pito::Slash::Dispatcher.call(input: raw, conversation: nil, authenticated:)
  end

  # ── Grammar-level recognition ───────────────────────────────────────────────
  describe "grammar-level recognition" do
    it "/help → stack :slash, verb :help, known: true" do
      intent = parsed_intent("/help")
      expect(intent[:stack]).to eq(:slash)
      expect(intent[:verb]).to eq(:help)
      expect(intent[:known]).to be(true)
    end

    it "/help is :any auth — accessible without authentication" do
      expect(parsed_intent("/help")[:auth]).to eq(:any)
    end

    # The parser downcases the token before the registry lookup.
    %w[/HELP /Help /hElp /HELP].each do |variant|
      it "#{variant} → verb :help, auth :any, known: true (parser downcases)" do
        intent = parsed_intent(variant)
        expect(intent[:stack]).to eq(:slash)
        expect(intent[:verb]).to eq(:help)
        expect(intent[:auth]).to eq(:any)
        expect(intent[:known]).to be(true)
      end
    end

    it "/help has no registered aliases" do
      spec = Pito::Grammar::Registry.specs_for_alias(namespace: :slash, token: :help)
      expect(spec).not_to be_nil
      expect(spec.aliases).to be_empty
    end

    it "/help has no grammar slots (zero-arity command)" do
      spec = Pito::Grammar::Registry.specs_for_alias(namespace: :slash, token: :help)
      positional = spec.slots.reject { |s| s.kind == :kv || s.kind == :connective }
      expect(positional).to be_empty
    end
  end

  # ── Handler#call — authenticated: true → full sectioned help ───────────────
  describe "authenticated: true → full help (body + labels + sections)" do
    subject(:result) { build_handler(authenticated: true).call }

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "emits exactly one system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload contains body: (non-blank rendered copy string)" do
      expect(result.events.first[:payload][:body]).to be_a(String).and be_present
    end

    it "payload contains expand_label: (non-blank string)" do
      expect(result.events.first[:payload][:expand_label]).to be_a(String).and be_present
    end

    it "payload contains collapse_label: (non-blank string)" do
      expect(result.events.first[:payload][:collapse_label]).to be_a(String).and be_present
    end

    it "payload contains sections: (non-empty array)" do
      expect(result.events.first[:payload][:sections]).to be_an(Array).and be_present
    end

    it "sections include a COMMANDS section listing slash verbs (rows with /… keys)" do
      sections = result.events.first[:payload][:sections]
      commands = sections.find { |s| s[:rows]&.any? { |r| r[:key].to_s.start_with?("/") } }
      expect(commands).to be_present, "expected a section with /verb rows"
      expect(commands[:rows]).to be_an(Array).and be_present
      expect(commands[:title]).to be_present
    end

    it "sections include a KEYBINDINGS section" do
      sections = result.events.first[:payload][:sections]
      keybindings = sections.find { |s| s[:rows]&.any? { |r| !r[:key].to_s.start_with?("/") } }
      expect(keybindings).to be_present, "expected a keybindings section"
      expect(keybindings[:title]).to be_present
    end

    it "each section row has :key and :value keys" do
      result.events.first[:payload][:sections].each do |section|
        section[:rows].each do |row|
          expect(row).to have_key(:key)
          expect(row).to have_key(:value)
        end
      end
    end

    it "does NOT contain message_key: (that is the restricted path)" do
      expect(result.events.first[:payload]).not_to have_key(:message_key)
    end

    it "COMMANDS rows are sorted alphabetically by key" do
      sections = result.events.first[:payload][:sections]
      commands = sections.find { |s| s[:rows]&.any? { |r| r[:key].to_s.start_with?("/") } }
      keys = commands[:rows].map { |r| r[:key] }
      expect(keys).to eq(keys.sort)
    end

    it "/help itself appears in the commands section" do
      sections = result.events.first[:payload][:sections]
      all_keys = sections.flat_map { |s| s[:rows].map { |r| r[:key] } }
      expect(all_keys).to include("/help")
    end
  end

  # ── Handler#call — authenticated: false → restricted (login instruction) ───
  describe "authenticated: false → restricted help (unauthenticated login instruction)" do
    subject(:result) { build_handler(authenticated: false).call }

    it "returns Result::Ok (NOT an error — /help is accessible unauthenticated)" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "emits exactly one system event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload contains message_key: 'pito.slash.help.unauthenticated'" do
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.help.unauthenticated")
    end

    it "payload does NOT contain body: (that is the full-help path)" do
      expect(result.events.first[:payload]).not_to have_key(:body)
    end

    it "payload does NOT contain sections:" do
      expect(result.events.first[:payload]).not_to have_key(:sections)
    end

    it "payload does NOT contain expand_label: or collapse_label:" do
      payload = result.events.first[:payload]
      expect(payload).not_to have_key(:expand_label)
      expect(payload).not_to have_key(:collapse_label)
    end

    it "handler does NOT check help? in #call — auth branch is the only gate" do
      # When called directly with --help in raw, the handler still follows the
      # authenticated branch (NOT show_help). The --help intercept lives solely
      # in the Dispatcher. This verifies the invariant.
      inv = Pito::Slash::Invocation.new(verb: :help, args: [], kwargs: {}, raw: "/help --help")
      handler = Pito::Slash::Handlers::Help.new(invocation: inv, conversation: nil, authenticated: false)
      result = handler.call
      # Should return restricted_help, NOT the nonsense man-page.
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.help.unauthenticated")
    end
  end

  # ── Auth split via the Dispatcher (end-to-end, no DB) ──────────────────────
  describe "Dispatcher — auth :any: both auth states reach the handler" do
    it "bare /help (authenticated: true) → full help Result::Ok via Dispatcher" do
      result = dispatch("/help", authenticated: true)
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:sections]).to be_an(Array).and be_present
    end

    it "bare /help (authenticated: false) → restricted Result::Ok via Dispatcher (NOT error)" do
      result = dispatch("/help", authenticated: false)
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.help.unauthenticated")
    end
  end

  # ── --help / -h intercept: Dispatcher → HelpBuilder → nonsense man-page ────
  #
  # The dispatcher intercepts `--help` / `-h` BEFORE constructing the handler,
  # so /help --help never calls Help#call at all — it goes straight to
  # HelpBuilder which routes verb "help" to the nonsense easter-egg man-page.
  describe "--help / -h flag → Dispatcher intercept → nonsense man-page" do
    {
      "/help --help" => "bare --help",
      "/help -h"     => "bare -h"
    }.each do |raw, label|
      it "#{raw.inspect} (#{label}) → Result::Ok with html: true" do
        result = dispatch(raw, authenticated: true)
        expect(result).to be_a(Pito::Slash::Result::Ok)
        expect(result.events.first[:payload]["html"]).to be(true)
      end

      it "#{raw.inspect} (#{label}) → body contains .pito-help-block" do
        result = dispatch(raw, authenticated: true)
        expect(result.events.first[:payload]["body"]).to include("pito-help-block")
      end
    end

    it "/help --help produces the nonsense man-page (not the full sectioned help)" do
      result = dispatch("/help --help", authenticated: true)
      body = result.events.first[:payload]["body"]
      # The nonsense_title ("Congratulations. You've reached the manual's manual.") anchors this.
      expect(body).to include("Congratulations")
    end

    it "/help --help does NOT contain the normal sections payload structure" do
      result = dispatch("/help --help", authenticated: true)
      # HelpBuilder returns a system event with string-keyed "html"/"body" — NOT symbol :sections
      expect(result.events.first[:payload]).not_to have_key(:sections)
    end

    it "/help -h with authenticated: false → still returns the nonsense man-page (auth :any + intercepted)" do
      result = dispatch("/help -h", authenticated: false)
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload]["html"]).to be(true)
    end

    it "/help --help with authenticated: false → nonsense man-page (not restricted_help)" do
      result = dispatch("/help --help", authenticated: false)
      expect(result).to be_a(Pito::Slash::Result::Ok)
      # This is the HelpBuilder path (html:true), NOT restricted_help (message_key:)
      expect(result.events.first[:payload]).to have_key("html")
      expect(result.events.first[:payload]).not_to have_key(:message_key)
    end
  end

  # ── Arity guard — /help accepts no positional arguments ────────────────────
  #
  # Grammar declares zero slots → Dispatcher capacity = 0.
  # Any positional arg trips the arity guard UNLESS --help is in the raw
  # (--help is intercepted first and never reaches the guard).
  describe "arity guard — /help takes no positional arguments" do
    it "/help extra_arg → too_many_args error" do
      result = dispatch("/help extra_arg")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.too_many_args")
    end

    it "/help foo bar → too_many_args error (multiple extra args)" do
      result = dispatch("/help foo bar")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.too_many_args")
    end

    it "/help foo (authenticated: false) → too_many_args error (arity checked before auth-branch)" do
      result = dispatch("/help foo", authenticated: false)
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.too_many_args")
    end

    it "/help --help extra (--help intercepted first → nonsense man-page, no arity error)" do
      # --help is intercepted BEFORE the arity guard, so even with extra tokens
      # the result is the man-page, not a too_many_args error.
      result = dispatch("/help --help extra")
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload]).to have_key("html")
    end
  end
end
