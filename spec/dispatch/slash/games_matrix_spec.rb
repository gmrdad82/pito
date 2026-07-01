# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/games` (recognition + handler, DB-free) ────────────────
#
# RULE: every kwarg combination recognised by the handler — no exception.
# The Games handler touches NO database; zero factories, zero DB stubs needed.
# We invoke the handler directly (bypassing the dispatcher) so every branch is
# exercised without auth-interception or routing noise.
#
# Branches (source: app/services/pito/slash/handlers/games.rb #call):
#
#   1. help?                              → show_help (man-page, html: true)
#   2. args.first blank / missing         → usage_hint (Pito::Copy text)
#   3. args.first == "import" (any case)
#        args.size >= 2                   → prefill = args[1..].join(" ")
#        args.size == 1                   → prefill extracted from raw via regex
#   4. args.first ∈ anything else         → usage_hint (witty fallback)
#   5. Grammar / auth tier               → :authenticated_only
#
# Notation:
#   Result::Ok    — handler accepted input; events emitted.
#   Result::Error — NOT used by this handler. Every branch (bare, unknown,
#                   import) returns Result::Ok. There are no Error paths.
RSpec.describe "Dispatch matrix — /games (recognition, DB mocked)", type: :dispatch do
  let(:conversation) { double("conversation") }

  # Build and invoke the handler directly, bypassing the dispatcher so we can
  # exercise every branch without routing concerns or auth interception.
  def call_handler(args: [], kwargs: {}, raw: nil, authenticated: true)
    invocation = Pito::Slash::Invocation.new(
      verb:   :games,
      args:   args,
      kwargs: kwargs,
      raw:    raw || [ "/games", *args ].join(" ")
    )
    Pito::Slash::Handlers::Games.new(invocation:, conversation:, authenticated:).call
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 0. Grammar / auth-tier recognition (parsed_intent, no handler involved)
  # ═══════════════════════════════════════════════════════════════════════════
  describe "grammar recognition" do
    it "/games resolves to verb :games on the :slash stack (known)" do
      expect(parsed_intent("/games")).to include(stack: :slash, verb: :games, known: true)
    end

    it "/games is gated as :authenticated_only" do
      expect(parsed_intent("/games")[:auth]).to eq(:authenticated_only)
    end

    it "/games import resolves as :games (subcommand is a positional arg, not a separate verb)" do
      expect(parsed_intent("/games import")).to include(stack: :slash, verb: :games, known: true)
    end

    it "/games import <single-word title> resolves as :games" do
      expect(parsed_intent("/games import Celeste")).to include(stack: :slash, verb: :games, known: true)
    end

    it "/games import <multi-word title> resolves as :games" do
      expect(parsed_intent("/games import The Witcher 3")).to include(stack: :slash, verb: :games, known: true)
    end

    it "/games --help resolves as :games" do
      expect(parsed_intent("/games --help")).to include(stack: :slash, verb: :games, known: true)
    end

    it "/games <unknown-subcommand> resolves as :games (handler routes, not grammar)" do
      expect(parsed_intent("/games frobnicate")).to include(stack: :slash, verb: :games, known: true)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. --help intercept
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/games --help" do
    # The handler's help? checks invocation.raw.match?(/--help\b/).
    # When called directly (no dispatcher), the handler's own show_help fires.
    let(:result) { call_handler(raw: "/games --help") }

    it "returns Result::Ok (not Result::Error)" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "emits exactly one event" do
      expect(result.events.size).to eq(1)
    end

    it "event kind is the string 'system'" do
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload carries html: true (man-page flag, string key)" do
      expect(result.events.first[:payload]["html"]).to be(true)
    end

    it "payload carries a 'body' key (string key)" do
      expect(result.events.first[:payload]).to have_key("body")
    end

    it "body includes the pito-help-block container class" do
      expect(result.events.first[:payload]["body"]).to include("pito-help-block")
    end

    it "body mentions the 'import' subcommand" do
      expect(result.events.first[:payload]["body"]).to include("import"),
        "expected --help body to list the 'import' subcommand"
    end

    it "body includes the --help option" do
      expect(result.events.first[:payload]["body"]).to include("--help")
    end

    it "does NOT open the import sidebar" do
      expect(result.events.first[:payload]).not_to have_key("sidebar_open")
      expect(result.events.first[:payload]).not_to have_key(:sidebar_open)
    end
  end

  # --help is raw-string matched; extra trailing args do not prevent interception
  describe "/games --help with trailing args" do
    let(:result) { call_handler(args: [ "import" ], raw: "/games import --help") }

    it "returns Result::Ok via show_help" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "payload html: true (man-page path, not import sidebar)" do
      expect(result.events.first[:payload]["html"]).to be(true)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. bare /games → usage_hint
  # ═══════════════════════════════════════════════════════════════════════════
  describe "bare /games (args: [])" do
    let(:result) { call_handler(args: []) }
    let(:payload) { result.events.first[:payload] }

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "emits exactly one event" do
      expect(result.events.size).to eq(1)
    end

    it "event kind is 'system'" do
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload contains :text (usage_hint copy)" do
      expect(payload).to have_key(:text)
    end

    it "payload does not open the sidebar" do
      expect(payload).not_to have_key(:sidebar_open)
    end

    it "payload :text equals the import_usage copy render" do
      expect(payload[:text]).to eq(Pito::Copy.render("pito.copy.games.import_usage"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. /games import (no title) → open_import_sidebar, blank prefill
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/games import (no title, args: ['import'])" do
    let(:result) { call_handler(args: [ "import" ], raw: "/games import") }
    let(:payload) { result.events.first[:payload] }

    it "returns Result::Ok" do
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "emits exactly one event" do
      expect(result.events.size).to eq(1)
    end

    it "event kind is 'system'" do
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "payload contains sidebar_open: 'games_import'" do
      expect(payload[:sidebar_open]).to eq("games_import")
    end

    it "prefill is blank (no title supplied)" do
      expect(payload[:prefill]).to eq("")
    end

    it "payload :text is the import opening i18n copy" do
      expect(payload[:text]).to eq(I18n.t("pito.slash.games.import.opening"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 4. /games import <title> → open_import_sidebar, prefill set
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/games import <title>" do
    # Title from args[1..] path (args.size >= 2)
    context "single-word title (args: ['import', 'Celeste'])" do
      let(:result) { call_handler(args: %w[import Celeste], raw: "/games import Celeste") }
      let(:payload) { result.events.first[:payload] }

      it "returns Result::Ok" do
        expect(result).to be_a(Pito::Slash::Result::Ok)
      end

      it "sidebar_open is 'games_import'" do
        expect(payload[:sidebar_open]).to eq("games_import")
      end

      it "prefill equals the single title word" do
        expect(payload[:prefill]).to eq("Celeste")
      end

      it "payload :text is the opening i18n copy" do
        expect(payload[:text]).to eq(I18n.t("pito.slash.games.import.opening"))
      end
    end

    context "multi-word title (args: ['import', 'The', 'Witcher', '3'])" do
      let(:result) do
        call_handler(args: %w[import The Witcher 3], raw: "/games import The Witcher 3")
      end
      let(:payload) { result.events.first[:payload] }

      it "returns Result::Ok" do
        expect(result).to be_a(Pito::Slash::Result::Ok)
      end

      it "sidebar_open is 'games_import'" do
        expect(payload[:sidebar_open]).to eq("games_import")
      end

      it "prefill joins all title words with a space" do
        expect(payload[:prefill]).to eq("The Witcher 3")
      end
    end

    context "title with special characters (apostrophe, numeral)" do
      let(:result) do
        call_handler(
          args: [ "import", "Baldur's", "Gate", "3" ],
          raw:  "/games import Baldur's Gate 3"
        )
      end
      let(:payload) { result.events.first[:payload] }

      it "prefill preserves the full title including apostrophe" do
        expect(payload[:prefill]).to eq("Baldur's Gate 3")
      end
    end

    # Title from raw regex path (args.size < 2, i.e. args == ['import'])
    context "title extracted from raw when args has only ['import'] (regex fallback path)" do
      let(:result) { call_handler(args: [ "import" ], raw: "/games import Hollow Knight") }
      let(:payload) { result.events.first[:payload] }

      it "returns Result::Ok" do
        expect(result).to be_a(Pito::Slash::Result::Ok)
      end

      it "sidebar_open is 'games_import'" do
        expect(payload[:sidebar_open]).to eq("games_import")
      end

      it "prefill is extracted from the raw string (multi-word via regex)" do
        expect(payload[:prefill]).to eq("Hollow Knight")
      end
    end

    context "raw has only 'import' with no trailing title text (raw regex yields blank)" do
      # Demonstrates the two paths both yield "" when no title is present.
      let(:result) { call_handler(args: [ "import" ], raw: "/games import") }

      it "prefill is blank" do
        expect(result.events.first[:payload][:prefill]).to eq("")
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 5. Case insensitivity for 'import'
  # ═══════════════════════════════════════════════════════════════════════════
  describe "case insensitivity for 'import' subcommand" do
    # The handler downcases args.first before the case branch.
    %w[IMPORT Import iMpOrT].each do |variant|
      context "args.first = #{variant.inspect}" do
        let(:result) { call_handler(args: [ variant ]) }

        it "routes to open_import_sidebar (payload contains :sidebar_open)" do
          expect(result).to be_a(Pito::Slash::Result::Ok)
          expect(result.events.first[:payload]).to have_key(:sidebar_open)
        end

        it "sidebar_open is 'games_import'" do
          expect(result.events.first[:payload][:sidebar_open]).to eq("games_import")
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 6. Unknown subcommand → usage_hint (witty fallback, NOT Result::Error)
  # ═══════════════════════════════════════════════════════════════════════════
  describe "unknown subcommand → usage_hint" do
    # The handler's else branch routes every unrecognised first arg back to
    # usage_hint — always Result::Ok with :text, never Result::Error.
    [
      "export",
      "list",
      "delete",
      "search",
      "remove",
      "add",
      "edit",
      "show",
      "update",
      "help",     # bare "help" (without --) is NOT recognised — falls to unknown
      "foo",
      "bar",
      "bogus"
    ].each do |sub|
      context "subcommand #{sub.inspect}" do
        let(:result) { call_handler(args: [ sub ]) }

        it "returns Result::Ok (not Result::Error)" do
          expect(result).to be_a(Pito::Slash::Result::Ok)
        end

        it "emits exactly one event" do
          expect(result.events.size).to eq(1)
        end

        it "payload contains :text (usage_hint path)" do
          expect(result.events.first[:payload]).to have_key(:text)
        end

        it "payload does NOT contain :sidebar_open (not routed to import)" do
          expect(result.events.first[:payload]).not_to have_key(:sidebar_open)
        end

        it "usage text equals the import_usage Copy render" do
          expect(result.events.first[:payload][:text]).to eq(
            Pito::Copy.render("pito.copy.games.import_usage")
          )
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 7. Auth gating
  # ═══════════════════════════════════════════════════════════════════════════
  describe "auth gating" do
    it "grammar spec declares :authenticated_only for /games" do
      expect(parsed_intent("/games")[:auth]).to eq(:authenticated_only)
    end

    it "grammar spec declares :authenticated_only for /games import" do
      expect(parsed_intent("/games import")[:auth]).to eq(:authenticated_only)
    end

    it "grammar spec declares :authenticated_only for /games import <title>" do
      expect(parsed_intent("/games import Celeste")[:auth]).to eq(:authenticated_only)
    end

    # The handler itself does NOT enforce auth — auth rejection is the
    # controller's responsibility (before the dispatcher is invoked).
    # These tests document that the handler still executes normally when
    # authenticated: false (so the grammar spec is the only auth gate in tests).
    context "when authenticated: false (handler-level — auth enforced upstream)" do
      it "bare /games still returns Result::Ok" do
        result = call_handler(args: [], authenticated: false)
        expect(result).to be_a(Pito::Slash::Result::Ok)
      end

      it "/games import still opens the sidebar" do
        result = call_handler(args: [ "import" ], raw: "/games import", authenticated: false)
        expect(result).to be_a(Pito::Slash::Result::Ok)
        expect(result.events.first[:payload][:sidebar_open]).to eq("games_import")
      end

      it "/games <unknown> still returns Result::Ok (usage_hint)" do
        result = call_handler(args: [ "bogus" ], authenticated: false)
        expect(result).to be_a(Pito::Slash::Result::Ok)
        expect(result.events.first[:payload]).to have_key(:text)
      end
    end
  end
end
