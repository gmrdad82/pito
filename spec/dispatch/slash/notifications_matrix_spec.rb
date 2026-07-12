# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/notifs` (recognition + result shape, zero DB) ───────────
#
# RULE: every recognized invocation is verified here. No exception.
#
# Architecture notes
# ------------------
# Handler:  Pito::Slash::Handlers::Notifications, verb :notifs
# Registry: lives in BOTH Pito::Slash::Registry AND Pito::Grammar::Registry.
#   • The grammar spec (name: :notifs, slots: [], auth: :authenticated_only) is
#     auto-registered at boot via register_handler_specs; this is confirmed by
#     the autosuggest test in notifications_spec.rb.
#   • The handler registry (Slash::Registry) maps :notifs → Notifications.
#
# Dispatch pipeline (Pito::Slash::Dispatcher):
#   Lexer → KeywordSanitizer → Parser → help interception → Slash::Registry
#   → arity guard → Handler#call
#
# Key behavioral facts (from source):
#   1. Verb is :notifs — NOT :notifications. "/notifications" produces verb
#      :notifications, which is absent from Slash::Registry → unknown_tool error.
#   2. "notifs" is NOT in KeywordSanitizer::KEYWORDS (unlike "themes"), so
#      case variants (/NOTIFS, /Notifs) are never normalised → unknown_tool.
#   3. "--help" / "-h" are intercepted by the dispatcher BEFORE handler runs
#      (regex /\s--help\b|\s-h\b/ on raw input). The handler has NO help? guard.
#      For verb "notifs" the HelpBuilder returns generic command help (not the
#      nonsense easter egg — that's only for "help" and "themes").
#   4. The grammar spec has slots: [] (0 positional slots, not unbounded). The
#      dispatcher's arity guard rejects any extra positional arg with too_many_args
#      BEFORE the handler is instantiated.  Handler-level leniency ("any extra
#      tokens ignored") applies only when the handler is invoked directly.
#   5. Auth gating: the handler does not check @authenticated. The dispatcher
#      also performs no auth check — enforcement is a controller-layer concern.
#
# `conversation` is a bare double — Notifications#call never calls methods on
# it during the stubbed broadcast path.  No factories, no DB persistence.
RSpec.describe "Dispatch matrix — /notifs (recognition, broadcaster mocked)", type: :dispatch do
  let(:conversation) { double("conversation") }

  # Defensive: ensure both registries are populated regardless of prior spec teardown.
  before { Pito::Slash::Registry.register_all! }

  # Stub the cable broadcast so no ActionCable write occurs.
  before do
    allow_any_instance_of(Pito::Stream::Broadcaster)
      .to receive(:broadcast_notifications_sidebar)
  end

  def dispatch(input, authenticated: true)
    Pito::Slash::Dispatcher.call(input:, conversation:, authenticated:)
  end

  # Asserts the canonical success result: sidebar_open: "notifications".
  def expect_sidebar_ok(result)
    expect(result).to be_a(Pito::Slash::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload][:sidebar_open]).to eq("notifications")
    expect(event[:payload][:text]).to be_present
  end

  # Asserts the generic --help man-page result (not the nonsense easter egg).
  def expect_generic_help(result)
    expect(result).to be_a(Pito::Slash::Result::Ok)
    payload = result.events.first[:payload]
    expect(payload["html"]).to be(true)
    expect(payload["body"]).to include("pito-help-block")
    # Not the nonsense easter egg (that's for help / themes)
    expect(payload[:sidebar_open]).to be_nil
  end

  # Asserts an unknown-verb error.
  def expect_unknown_tool(result, tool: nil)
    expect(result).to be_a(Pito::Slash::Result::Error)
    expect(result.message_key).to eq("pito.slash.errors.unknown_tool")
    expect(result.message_args[:tool]).to eq(tool) if tool
  end

  # Asserts an arity error (too many positional args).
  def expect_too_many_args(result)
    expect(result).to be_a(Pito::Slash::Result::Error)
    expect(result.message_key).to eq("pito.slash.errors.too_many_args")
  end

  # ── 0. Grammar / auth-tier recognition ────────────────────────────────────────

  describe "grammar recognition" do
    it "/notifications (canonical) → known: true on :slash stack" do
      intent = parsed_intent("/notifications")
      expect(intent).to include(stack: :slash, tool: :notifications, known: true)
    end

    it "/notifs (alias) → canonicalises to :notifications, known: true" do
      expect(parsed_intent("/notifs")).to include(stack: :slash, tool: :notifications, known: true)
    end

    it "is gated as :authenticated_only in the grammar spec" do
      expect(parsed_intent("/notifications")[:auth]).to eq(:authenticated_only)
    end

    it "the canonical grammar spec is registered under :notifications with the :notifs alias" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :notifications)
      expect(spec).not_to be_nil
      expect(spec.aliases).to include(:notifs)
      positional = spec.slots.reject { |s| s.kind == :kv || s.kind == :connective }
      expect(positional).to be_empty
    end
  end

  # ── 1. Bare `/notifs` — opens sidebar ─────────────────────────────────────────

  describe "bare /notifs" do
    it "/notifs → Ok (sidebar opens)" do
      expect_sidebar_ok(dispatch("/notifs"))
    end

    it "/notifs with trailing spaces → Ok" do
      expect_sidebar_ok(dispatch("/notifs   "))
    end

    it "emits exactly one event" do
      result = dispatch("/notifs")
      expect(result.events.size).to eq(1)
    end

    it "calls broadcast_notifications_sidebar on the broadcaster" do
      broadcaster = instance_double(Pito::Stream::Broadcaster,
                                    broadcast_notifications_sidebar: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).with(conversation:)
        .and_return(broadcaster)
      dispatch("/notifs")
      expect(broadcaster).to have_received(:broadcast_notifications_sidebar).once
    end
  end

  # ── 2. Extra tokens — arity guard rejects before handler ──────────────────────
  #
  # The grammar spec for :notifs has slots: [] (zero positional slots, not
  # unbounded). The dispatcher's generic arity guard rejects any extra positional
  # argument before the handler is instantiated, returning too_many_args.
  #
  # This is distinct from handler-level behaviour: the handler itself is lenient
  # and ignores args, but it is never reached when extra tokens are present.
  #
  # User-visible meaning: on/off/toggle/status are NOT subcommands. The command
  # has one form — bare `/notifs`. Extra words are always an error at this level.

  describe "extra positional tokens — rejected by dispatcher arity guard (capacity: 0)" do
    {
      "/notifs on"             => "'on' treated as positional arg",
      "/notifs off"            => "'off' treated as positional arg",
      "/notifs toggle"         => "'toggle' treated as positional arg",
      "/notifs enable"         => "'enable' treated as positional arg",
      "/notifs disable"        => "'disable' treated as positional arg",
      "/notifs status"         => "'status' treated as positional arg",
      "/notifs open"           => "'open' treated as positional arg",
      "/notifs read"           => "'read' treated as positional arg",
      "/notifs whatever"       => "unknown word",
      "/notifs foo bar"        => "multiple unknown words"
    }.each do |input, desc|
      it "#{input.inspect} (#{desc}) → Error: too_many_args" do
        expect_too_many_args(dispatch(input))
      end
    end

    it "too_many_args message_args includes the tool" do
      result = dispatch("/notifs on")
      expect(result.message_args[:tool]).to eq(:notifs)
    end
  end

  # ── 3. Kwarg-style inputs bypass arity guard ───────────────────────────────────
  #
  # The arity guard counts `invocation.args` (positional). Kwargs (key=value /
  # key: value syntax) do not increment args count — they flow to `invocation.kwargs`
  # which the handler ignores. So kwarg-style inputs reach the handler and open the
  # sidebar.

  describe "kwarg-style inputs (bypass arity guard, handler ignores kwargs)" do
    it "/notifs state=on → Ok (kwarg, not a positional arg)" do
      expect_sidebar_ok(dispatch("/notifs state=on"))
    end

    it "/notifs state=off → Ok" do
      expect_sidebar_ok(dispatch("/notifs state=off"))
    end
  end

  # ── 4. `--help` / `-h` intercept (BEFORE handler and BEFORE arity guard) ──────
  #
  # The dispatcher intercepts --help/-h via regex /\s--help\b|\s-h\b/ on the raw
  # input. This fires BEFORE the arity guard, so even inputs that would otherwise
  # fail arity return Ok with a man-page payload.
  #
  # For verb "notifs" HelpBuilder calls generic_command_help("notifs") — not the
  # nonsense easter egg (that's reserved for "help" and "themes").
  #
  # The intercept regex requires a WHITESPACE before the flag, so "/notifs--help"
  # (no space) is NOT intercepted.

  describe "--help / -h interception (before arity guard)" do
    [
      "/notifs --help",
      "/notifs -h"
    ].each do |input|
      it "#{input.inspect} → Ok (generic man-page help)" do
        expect_generic_help(dispatch(input))
      end
    end

    it "/notifs --help body includes Usage:" do
      result = dispatch("/notifs --help")
      expect(result.events.first[:payload]["body"]).to include("Usage:")
    end

    it "/notifs --help body includes /notifs (usage line)" do
      result = dispatch("/notifs --help")
      expect(result.events.first[:payload]["body"]).to include("notifs")
    end

    it "/notifs --help fires before arity guard — also works with extra positional tokens" do
      # Even though /notifs on would fail arity, --help intercepts first
      expect_generic_help(dispatch("/notifs on --help"))
    end

    it "/notifs --help → broadcaster NOT called (handler never runs)" do
      broadcaster = instance_double(Pito::Stream::Broadcaster,
                                    broadcast_notifications_sidebar: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      dispatch("/notifs --help")
      expect(broadcaster).not_to have_received(:broadcast_notifications_sidebar)
    end

    it "--help NOT intercepted when missing leading whitespace: /notifs--help → unknown_tool" do
      # The lexer treats `notifs--help` as a single :word token (hyphens are
      # word chars). Verb becomes :"notifs--help" — absent from Slash::Registry.
      result = dispatch("/notifs--help")
      expect_unknown_tool(result, tool: :"notifs--help")
    end

    it "--help NOT intercepted when uppercase: /notifs --HELP → arity error (not help)" do
      # Intercept regex /\s--help\b/ is case-sensitive. --HELP passes through
      # and is treated as a positional arg, triggering the arity guard.
      expect_too_many_args(dispatch("/notifs --HELP"))
    end

    it "-h NOT intercepted when uppercase: /notifs -H → arity error" do
      # -H is not matched by /\s-h\b/ (case-sensitive).
      expect_too_many_args(dispatch("/notifs -H"))
    end
  end

  # ── 5. Case normalization ─────────────────────────────────────────────────────
  #
  # "notifs" is NOT in Pito::Lex::KeywordSanitizer::KEYWORDS (unlike "themes").
  # Therefore mixed-case or uppercase variants of the verb are never normalised
  # and produce verb symbols that are absent from Slash::Registry.
  #
  # "notifications" (the user-visible name) is also absent from KEYWORDS and from
  # Slash::Registry — it's a recognition bug: the command is documented as
  # `/notifications` but the registered verb is `:notifs`.

  describe "case normalization — notifs/notifications ARE in KEYWORDS, variants normalise → Ok" do
    [ "/NOTIFS", "/Notifs", "/nOtIfS", "/NOTIFICATIONS", "/Notifications" ].each do |input|
      it "#{input.inspect} → Ok (sanitizer downcases the keyword → opens sidebar)" do
        expect_sidebar_ok(dispatch(input))
      end
    end
  end

  # ── 6. `/notifications` (canonical form) — dispatches like /notifs ─────────────
  #
  # `notifications` is the canonical verb (owner-decided: shown/autosuggested in
  # the palette). It opens the sidebar exactly like the `/notifs` alias.

  describe "/notifications (canonical form) dispatches" do
    it "/notifications → Ok (sidebar opens)" do
      expect_sidebar_ok(dispatch("/notifications"))
    end

    it "/notifications on → Error: too_many_args (zero-slot arity guard)" do
      expect_too_many_args(dispatch("/notifications on"))
    end

    it "/notifications --help → Ok (generic man-page help)" do
      expect_generic_help(dispatch("/notifications --help"))
    end
  end

  # ── 7. Auth gating — handler/dispatcher pass-through ─────────────────────────
  #
  # The grammar DSL declares `auth :authenticated_only`. That metadata lives in
  # Grammar::Registry and is used for autocomplete/suggestions. The dispatcher
  # performs NO auth check before calling the handler. The handler ignores
  # @authenticated. Auth enforcement is the controller's responsibility.

  describe "auth gating — authenticated: false passes through to handler" do
    it "/notifs with authenticated: false → Ok (handler opens sidebar regardless)" do
      expect_sidebar_ok(dispatch("/notifs", authenticated: false))
    end

    it "/notifs --help with authenticated: false → Ok (help still returned)" do
      expect_generic_help(dispatch("/notifs --help", authenticated: false))
    end

    it "/notifications (canonical) with authenticated: false → Ok (handler opens regardless)" do
      expect_sidebar_ok(dispatch("/notifications", authenticated: false))
    end
  end

  # ── 8. Slash::Registry lookup — the resolver layer ───────────────────────────

  describe "Slash::Registry lookup" do
    it "Registry.lookup(:notifications) returns the Notifications handler (canonical)" do
      expect(Pito::Slash::Registry.lookup(:notifications))
        .to eq(Pito::Slash::Handlers::Notifications)
    end

    it "Registry.lookup(:notifs) returns the Notifications handler (alias)" do
      expect(Pito::Slash::Registry.lookup(:notifs))
        .to eq(Pito::Slash::Handlers::Notifications)
    end

    it "handler verb is :notifications" do
      expect(Pito::Slash::Handlers::Notifications.tool).to eq(:notifications)
    end
  end
end
