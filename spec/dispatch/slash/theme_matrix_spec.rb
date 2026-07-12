# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/themes` (recognition + result shape, zero DB) ──────────
#
# RULE: every recognized invocation is verified here. No exception.
# Assertions reflect what the dispatcher ACTUALLY does — not what the handler
# comment claims. Where the two diverge, the divergence is called out as a
# RECOGNITION BUG.
#
# ══ RECOGNITION BUGS FOUND ════════════════════════════════════════════════════
#
# BUG 1 — `/themes <any-arg>` → too_many_args (not sidebar-open as claimed)
#
#   Pito::Slash::Handlers::Theme comment says:
#     "Any extra tokens after `/themes` are ignored — the command is lenient
#      and always opens the sidebar."
#
#   What actually happens:
#     The dispatcher's generic positional-arity guard fires BEFORE the handler.
#     The grammar DSL block in Theme registers a Pito::Grammar::Spec with
#     0 positional slots. The guard sees invocation.args.size > 0 > capacity(0)
#     and returns Result::Error(too_many_args) without ever calling #call.
#
#   Affected inputs (exhaustive):
#     /themes <any-slug>   — e.g. /themes tokyo-night
#     /themes default      — the registry's "default" alias
#     /themes <unknown>    — e.g. /themes bogus
#     /themes --HELP       — uppercase --help (not intercepted, treated as arg)
#     /themes -H           — uppercase -h (not intercepted, treated as arg)
#
#   Fix path (one of):
#     a) Add `self.validates_own_arity = true` to the handler (opt-out guard), OR
#     b) Add a `:free` positional slot in the `grammar do` block, OR
#     c) Remove the grammar block so no spec is found (arity guard skips nil spec)
#
# ══════════════════════════════════════════════════════════════════════════════
#
# Architecture notes
# ------------------
# Handler verb: :themes (PLURAL). Handler registry: Pito::Slash::Registry.
# Grammar registry: Pito::Grammar::Registry (also has a spec for :themes via
# the `grammar do` block, but with 0 positional slots — that's the bug above).
#
# Because :themes IS in Grammar::Registry, parsed_intent("/themes")[:known] is
# actually true (the slash_recognition_spec checks "/theme" singular, which IS
# unknown). The handler comment's framing ("not in grammar layer") was written
# about the singular "/theme" token, not the plural.
#
# `--help` / `-h` are intercepted by the dispatcher BEFORE the arity guard,
# so `/themes --help` and `/themes -h` still reach HelpBuilder. For verb
# "themes", HelpBuilder returns the nonsense "manual's manual" easter egg.
#
# `conversation` is a bare double — Theme#call never touches it.
# No factories, no DB persistence, no AppSetting writes.
RSpec.describe "Dispatch matrix — /themes (recognition, zero DB)", type: :dispatch do
  let(:conversation) { double("conversation") }

  # Defensive: ensure the handler registry contains Theme regardless of which
  # other spec ran before us (dispatcher_spec replaces and restores the registry
  # in an around block; this before re-populates after any such teardown).
  before { Pito::Slash::Registry.register_all! }

  def dispatch(input, authenticated: true)
    Pito::Slash::Dispatcher.call(input:, conversation:, authenticated:)
  end

  # Asserts a successful sidebar-open result from the Theme handler.
  def expect_sidebar_ok(result)
    expect(result).to be_a(Pito::Slash::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload][:sidebar_open]).to eq("theme")
    expect(event[:payload][:text]).to eq(I18n.t("pito.slash.theme.sidebar.opening"))
  end

  # Asserts the too_many_args arity guard error.
  def expect_too_many_args(result)
    expect(result).to be_a(Pito::Slash::Result::Error)
    expect(result.message_key).to eq("pito.slash.errors.too_many_args")
    expect(result.message_args[:tool]).to eq(:themes)
  end

  # Asserts the --help intercept nonsense easter egg (not a sidebar event).
  def expect_nonsense_help(result)
    expect(result).to be_a(Pito::Slash::Result::Ok)
    payload = result.events.first[:payload]
    expect(payload["html"]).to be(true)
    expect(payload["body"]).to include("pito-help-block")
    # Confirm this is NOT a sidebar event
    expect(payload[:sidebar_open]).to be_nil
  end

  # Asserts an unknown-verb error from the dispatcher.
  def expect_unknown_tool(result)
    expect(result).to be_a(Pito::Slash::Result::Error)
    expect(result.message_key).to eq("pito.slash.errors.unknown_tool")
  end

  # ── bare `/themes` ───────────────────────────────────────────────────────────

  describe "bare /themes (no args)" do
    it "/themes → Ok (sidebar opens)" do
      expect_sidebar_ok(dispatch("/themes"))
    end

    it "/themes with trailing spaces → Ok (sidebar opens)" do
      expect_sidebar_ok(dispatch("/themes   "))
    end
  end

  # ── /themes <each registered slug> — BUG 1 ──────────────────────────────────
  #
  # RECOGNITION BUG: The handler comment claims these all open the sidebar.
  # The dispatcher's arity guard rejects them with too_many_args before #call.
  # Every slug (valid or not) triggers the guard because the grammar spec has
  # 0 positional slots and the handler has validates_own_arity = false.

  describe "every registered theme slug → too_many_args (RECOGNITION BUG)" do
    THEME_SLUGS = %w[
      ayu-dark
      ayu-light
      ayu-mirage
      catppuccin-latte
      catppuccin-mocha
      dracula
      github-dark
      github-light
      gruvbox-dark
      gruvbox-light
      nord
      one-dark
      one-light
      solarized-dark
      solarized-light
      synthwave
      tokyo-night
      tomorrow
      tomorrow-night
    ].freeze

    THEME_SLUGS.each do |slug|
      it "/themes #{slug} → too_many_args (handler comment says ignored, arity guard disagrees)" do
        expect_too_many_args(dispatch("/themes #{slug}"))
      end
    end
  end

  # ── `default` — the registry's special alias — BUG 1 ────────────────────────
  #
  # RECOGNITION BUG: Pito::Themes::Registry.resolve_target("default") maps to
  # tokyo-night, but neither the slash handler nor the arity guard sees it —
  # the guard fires first with too_many_args.

  describe "/themes default (RECOGNITION BUG)" do
    it "/themes default → too_many_args (arity guard fires before handler)" do
      expect_too_many_args(dispatch("/themes default"))
    end
  end

  # ── unknown / garbage args — BUG 1 ───────────────────────────────────────────
  #
  # RECOGNITION BUG: The handler claims leniency for all args.
  # The arity guard fires regardless of arg content.

  describe "/themes <unrecognized arg> → too_many_args (RECOGNITION BUG)" do
    {
      "/themes bogus"         => "unknown slug",
      "/themes not-a-theme"   => "hyphenated unknown slug",
      "/themes 999"           => "numeric arg",
      "/themes unknown stuff" => "multiple garbage tokens",
      "/themes DARK"          => "uppercased unknown arg"
    }.each do |input, description|
      it "#{input.inspect} (#{description}) → too_many_args" do
        expect_too_many_args(dispatch(input))
      end
    end
  end

  # ── `--help` / `-h` intercept ────────────────────────────────────────────────
  #
  # The dispatcher intercepts these flags at step 2, BEFORE the arity guard
  # at step 4. For verb "themes", HelpBuilder returns the nonsense easter egg.
  # Intercept regex: /\s--help\b|\s-h\b/ — requires whitespace before the flag,
  # case-sensitive (--HELP and -H are NOT intercepted and fall to the arity guard).

  describe "--help and -h intercept → nonsense easter egg (not sidebar)" do
    [
      "/themes --help",
      "/themes -h",
      "/themes tokyo-night --help",   # --help intercept fires before arity guard
      "/themes bogus --help",          # same: --help wins over arity
      "/themes --help extra"
    ].each do |input|
      it "#{input.inspect} → Ok (nonsense easter egg)" do
        expect_nonsense_help(dispatch(input))
      end
    end
  end

  describe "--help NOT intercepted → arity guard fires" do
    it "/themes --HELP (uppercase) → too_many_args (not intercepted, arg counted)" do
      # Regex is case-sensitive. --HELP passes to arity guard as a positional arg.
      expect_too_many_args(dispatch("/themes --HELP"))
    end

    it "/themes -H (uppercase) → too_many_args (not intercepted, arg counted)" do
      expect_too_many_args(dispatch("/themes -H"))
    end

    it "/themes--help (no space before flag) → unknown_tool error" do
      # The lexer treats hyphens as word chars: `themes--help` tokenizes as ONE
      # :word token. Verb becomes :"themes--help", which is not in Slash::Registry.
      # The --help regex also does not match (no space before --help).
      result = dispatch("/themes--help")
      expect_unknown_tool(result)
      expect(result.message_args[:tool]).to eq(:"themes--help")
    end
  end

  # ── case normalization ────────────────────────────────────────────────────────
  #
  # Pito::Lex::KeywordSanitizer normalizes :word tokens whose downcased value is
  # in the KEYWORDS set. "themes" (plural) IS in KEYWORDS — so /THEMES, /Themes,
  # /tHeMeS all normalize to verb :themes.
  #
  # "theme" (singular) is NOT in KEYWORDS. Case variants of the singular form
  # (/THEME, /Theme) are not normalized and produce unknown-verb errors.

  describe "case normalization via KeywordSanitizer" do
    describe "plural bare variants (normalized to :themes → Ok sidebar)" do
      [ "/THEMES", "/Themes", "/tHeMeS" ].each do |input|
        it "#{input.inspect} → Ok (normalized to :themes, no args → sidebar opens)" do
          expect_sidebar_ok(dispatch(input))
        end
      end
    end

    describe "plural with arg variants (normalized to :themes but arity guard fires)" do
      it '"/THEMES tokyo-night" → too_many_args (normalized, then arity guard fires)' do
        expect_too_many_args(dispatch("/THEMES tokyo-night"))
      end
    end

    describe "singular variants (NOT normalized → unknown_tool error)" do
      {
        "/theme"  => :theme,
        "/THEME"  => :"THEME",
        "/Theme"  => :"Theme"
      }.each do |input, expected_tool|
        it "#{input.inspect} → unknown_tool error (tool #{expected_tool.inspect})" do
          result = dispatch(input)
          expect_unknown_tool(result)
          expect(result.message_args[:tool]).to eq(expected_tool)
        end
      end
    end
  end

  # ── `/theme` singular — not registered ──────────────────────────────────────
  #
  # The handler is registered under :themes (plural). `/theme` (singular)
  # produces verb :theme which exists in neither Slash::Registry nor
  # Grammar::Registry. This is BY DESIGN (see slash_recognition_spec.rb).

  describe "/theme (singular) — unknown verb" do
    it "/theme → Result::Error (unknown verb :theme)" do
      result = dispatch("/theme")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.unknown_tool")
      expect(result.message_args[:tool]).to eq(:theme)
    end

    it "/theme tokyo-night → Result::Error (still unknown verb :theme)" do
      result = dispatch("/theme tokyo-night")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.unknown_tool")
      expect(result.message_args[:tool]).to eq(:theme)
    end

    it "/theme default → Result::Error" do
      result = dispatch("/theme default")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.unknown_tool")
    end

    it "/theme --help → Ok (--help intercept fires before unknown_tool check)" do
      # The --help intercept fires at step 2; registry lookup is step 3.
      # So even /theme --help returns Ok (HelpBuilder handles any verb gracefully).
      result = dispatch("/theme --help")
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end
  end

  # ── auth gating ──────────────────────────────────────────────────────────────
  #
  # The grammar DSL declares `auth :authenticated_only` and the grammar spec for
  # :themes IS registered (it's how the arity guard finds 0 slots). However,
  # the dispatcher does NOT check the grammar spec's auth field — auth enforcement
  # lives in the controller layer, before the dispatcher is called.
  # Theme#call also ignores @authenticated entirely.
  #
  # Net effect: `authenticated: false` changes nothing at the dispatcher level.

  describe "auth gating — authenticated: false" do
    it "/themes with authenticated: false → Ok (handler opens sidebar regardless)" do
      expect_sidebar_ok(dispatch("/themes", authenticated: false))
    end

    it "/themes tokyo-night with authenticated: false → too_many_args (arity guard, not auth)" do
      # The too_many_args comes from the arity guard — the same result as authenticated.
      expect_too_many_args(dispatch("/themes tokyo-night", authenticated: false))
    end

    it "/themes --help with authenticated: false → Ok (nonsense help)" do
      expect_nonsense_help(dispatch("/themes --help", authenticated: false))
    end

    it "/theme with authenticated: false → Result::Error (still unknown verb)" do
      result = dispatch("/theme", authenticated: false)
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.unknown_tool")
    end
  end
end
