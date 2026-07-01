# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/rename` (recognition only, DB mocked) ──────────────────
#
# RULE: every form the handler recognises — no exception. `Conversation::Rename`
# is stubbed; zero factories, zero DB writes, no Conversation record created.
#
# Branches (source: app/services/pito/slash/handlers/rename.rb #call):
#
#   1. help?  (raw includes `--help\b`)      → show_help (handler-level man page)
#   2. new_title.blank?                      → needs_title (usage-hint Result::Ok)
#   3. title present                         → Conversation::Rename + system text event
#
# Grammar: `free :title, optional: true` — no kwargs. The handler reads the
# title exclusively from `invocation.raw` via:
#
#   invocation.raw.to_s.strip.sub(%r{\A/rename\b\s*}i, "").strip
#
# Note on dispatcher interaction: the dispatcher intercepts `--help` BEFORE
# calling the handler (Pito::Slash::HelpBuilder). The handler's own `help?` /
# `show_help` path is exercised only when calling the handler directly (as
# these specs do). Both paths produce the same Result::Ok shape; the content
# differs (handler's own man page includes "Arguments:" + `<new title>`).
#
# Auth tier: :authenticated_only — asserted via `parsed_intent`, not inside
# the handler itself (the dispatcher gates it upstream).
RSpec.describe "Dispatch matrix — /rename (recognition, DB mocked)", type: :dispatch do
  let(:conversation) { double("conversation") }

  # Construct and invoke the handler directly, bypassing the dispatcher so
  # every branch is reachable without routing concerns or auth interception.
  def call_handler(raw:, authenticated: true)
    invocation = Pito::Slash::Invocation.new(
      verb:   :rename,
      args:   [],
      kwargs: {},
      raw:    raw
    )
    Pito::Slash::Handlers::Rename.new(invocation:, conversation:, authenticated:).call
  end

  # Global stub — every test sees a clean Conversation::Rename that returns the
  # double.  Overridden per-context when failure behaviour is needed.
  before do
    allow(Conversation::Rename).to receive(:call).and_return(conversation)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 0. Grammar / auth-tier recognition
  # ═══════════════════════════════════════════════════════════════════════════
  describe "grammar recognition" do
    it "/rename resolves to verb :rename on the :slash stack (known)" do
      expect(parsed_intent("/rename")).to include(stack: :slash, verb: :rename, known: true)
    end

    it "/rename is gated as :authenticated_only" do
      expect(parsed_intent("/rename")[:auth]).to eq(:authenticated_only)
    end

    it "/rename My Channel still resolves — the title is a free arg, not a separate verb" do
      expect(parsed_intent("/rename My Channel")).to include(stack: :slash, verb: :rename, known: true)
    end

    it "/rename --help still resolves — --help is parsed as a flag, not a verb" do
      expect(parsed_intent("/rename --help")).to include(stack: :slash, verb: :rename, known: true)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. --help intercept (handler-level show_help)
  #
  # `help?` checks: invocation.raw.match?(/--help\b/)
  # The handler's own show_help builds a man page with "Arguments:" + "<new
  # title>" — distinct from HelpBuilder's generic "Description:" page.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "/rename --help" do
    {
      "bare --help"                    => "/rename --help",
      "--help before a title"          => "/rename --help My Channel",
      "--help after a title"           => "/rename My Channel --help",
      "--help with multi-word title"   => "/rename My Strategy Channel --help"
    }.each do |description, raw|
      context "#{description} (#{raw.inspect})" do
        let(:result) { call_handler(raw: raw) }

        it "returns Result::Ok (not an error)" do
          expect(result).to be_a(Pito::Slash::Result::Ok)
        end

        it "emits exactly one system event" do
          expect(result.events.size).to eq(1)
          expect(result.events.first[:kind]).to eq(:system)
        end

        it "payload carries html: true (man-page flag)" do
          expect(result.events.first[:payload]["html"]).to be(true)
        end

        it "payload body is wrapped in .pito-help-block" do
          expect(result.events.first[:payload]["body"]).to include("pito-help-block")
        end

        it "body includes the usage line from i18n (HTML-escaped by ManPage renderer)" do
          expected_usage = ERB::Util.html_escape(I18n.t("pito.slash.rename.help.usage"))
          expect(result.events.first[:payload]["body"]).to include(expected_usage)
        end

        it "body includes the <new title> argument description" do
          expect(result.events.first[:payload]["body"]).to include("new title")
        end

        it "body includes the --help option" do
          expect(result.events.first[:payload]["body"]).to include("--help")
        end

        it "does NOT call Conversation::Rename (pure help, no side effects)" do
          result
          expect(Conversation::Rename).not_to have_received(:call)
        end
      end
    end

    it "--helpsomething does NOT trigger help? (word-boundary guard)" do
      # /--help\b/ requires a non-word char after 'p'; --helpsomething fails.
      result = call_handler(raw: "/rename --helpsomething")
      expect(result).to be_a(Pito::Slash::Result::Ok)
      # Title is "--helpsomething", so Rename IS called.
      expect(Conversation::Rename).to have_received(:call)
        .with(conversation:, title: "--helpsomething")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. Blank title → needs_title usage hint
  #
  # new_title = raw.strip.sub(%r{\A/rename\b\s*}i, "").strip
  # Blank after extraction → usage-hint event (no rename call).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "bare /rename → needs_title" do
    {
      "bare verb"            => "/rename",
      "verb + spaces"        => "/rename   ",
      "verb + tab"           => "/rename\t",
      "verb + mixed space"   => "/rename \t  "
    }.each do |description, raw|
      context "#{description} (#{raw.inspect})" do
        let(:result) { call_handler(raw: raw) }

        it "returns Result::Ok" do
          expect(result).to be_a(Pito::Slash::Result::Ok)
        end

        it "emits exactly one system event" do
          expect(result.events.size).to eq(1)
          expect(result.events.first[:kind]).to eq(:system)
        end

        it "event kind is 'system'" do
          expect(result.events.first[:kind]).to eq(:system)
        end

        it "payload uses the symbol key :text (needs_title code path)" do
          expect(result.events.first[:payload]).to have_key(:text)
        end

        it "payload text equals the needs_title i18n string" do
          expected = I18n.t("pito.slash.rename.needs_title")
          expect(result.events.first[:payload][:text]).to eq(expected)
        end

        it "does NOT call Conversation::Rename" do
          result
          expect(Conversation::Rename).not_to have_received(:call)
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. Title present → successful rename
  #
  # Calls Conversation::Rename.call(conversation:, title:) then returns
  # Result::Ok with { kind: "system", payload: { "text" => <copy variant> } }.
  # All pito.copy.conversations.renamed variants interpolate %{title}, so the
  # rendered text always includes the supplied title.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "successful rename" do
    {
      # single word
      "/rename foo"                                => "foo",
      # multi-word (spaces preserved)
      "/rename My Strategy Channel"                => "My Strategy Channel",
      "/rename multi word title"                   => "multi word title",
      # numeric string
      "/rename 123"                                => "123",
      "/rename 2024-season"                        => "2024-season",
      # leading/trailing whitespace in raw (double-strip in new_title)
      "/rename   padded title   "                  => "padded title",
      # special ASCII characters
      "/rename foo!@#$%^&*()"                      => "foo!@#$%^&*()",
      # unicode
      "/rename café crème"                         => "café crème",
      # dashes that are NOT --help (no word boundary match)
      "/rename title with -- dashes"               => "title with -- dashes",
      "/rename -short-flag"                        => "-short-flag",
      # very long title (255 chars)
      "/rename " + ("x" * 255)                     => ("x" * 255),
      # single character
      "/rename X"                                  => "X"
    }.each do |raw, expected_title|
      context raw[0, 60].inspect do
        let(:result) { call_handler(raw: raw) }

        it "returns Result::Ok" do
          expect(result).to be_a(Pito::Slash::Result::Ok)
        end

        it "calls Conversation::Rename with conversation and extracted title" do
          result
          expect(Conversation::Rename).to have_received(:call)
            .with(conversation:, title: expected_title)
        end

        it "emits exactly one system event" do
          expect(result.events.size).to eq(1)
        end

        it "event kind is 'system'" do
          expect(result.events.first[:kind]).to eq(:system)
        end

        it "payload uses the string key 'text' (MessageBuilder::Text code path)" do
          expect(result.events.first[:payload]).to have_key("text")
        end

        it "payload text includes the new title (interpolated by copy variant)" do
          expect(result.events.first[:payload]["text"]).to include(expected_title[0, 100])
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 4. Case-insensitive verb extraction (new_title regex uses /i flag)
  #
  # The regex %r{\A/rename\b\s*}i strips the verb regardless of case, so
  # /RENAME foo and /Rename foo both extract the same title.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "case-insensitive /rename verb in raw" do
    {
      "/RENAME foo"            => "foo",
      "/Rename My Channel"     => "My Channel",
      "/RENAME   My Channel  " => "My Channel"
    }.each do |raw, expected_title|
      it "#{raw.inspect} extracts #{expected_title.inspect} as the title" do
        call_handler(raw: raw)
        expect(Conversation::Rename).to have_received(:call)
          .with(conversation:, title: expected_title)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 5. Payload shape distinction (needs_title vs success)
  #
  # needs_title uses { text: ... } (symbol key, I18n.t direct).
  # success      uses { "text" => ... } (string key, via MessageBuilder::Text).
  # Both produce kind: "system" (string).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "payload shape distinction between branches" do
    it "needs_title payload uses symbol key :text" do
      result = call_handler(raw: "/rename")
      expect(result.events.first[:payload].keys).to include(:text)
      expect(result.events.first[:payload].keys).not_to include("text")
    end

    it "success payload uses string key 'text'" do
      result = call_handler(raw: "/rename My Channel")
      expect(result.events.first[:payload].keys).to include("text")
      expect(result.events.first[:payload].keys).not_to include(:text)
    end

    it "both branches return Result::Ok (neither is Result::Error)" do
      expect(call_handler(raw: "/rename")).to be_a(Pito::Slash::Result::Ok)
      expect(call_handler(raw: "/rename My Channel")).to be_a(Pito::Slash::Result::Ok)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 6. No kwargs in grammar — free :title is the only slot
  #
  # The handler ignores invocation.args and invocation.kwargs entirely.
  # A "kwarg-style" token in raw (e.g. /rename title: foo) is treated as part
  # of the free title string — new_title sees "title: foo" as the title.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "kwarg-like tokens in raw are part of the title (no kwargs grammar)" do
    it "/rename title: foo → title is 'title: foo'" do
      call_handler(raw: "/rename title: foo")
      expect(Conversation::Rename).to have_received(:call)
        .with(conversation:, title: "title: foo")
    end

    it "/rename name=My Channel → title is 'name=My Channel'" do
      call_handler(raw: "/rename name=My Channel")
      expect(Conversation::Rename).to have_received(:call)
        .with(conversation:, title: "name=My Channel")
    end
  end
end
