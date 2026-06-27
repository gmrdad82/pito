# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/disconnect` (recognition only, DB mocked) ──────────────
#
# RULE: every input form the handler recognises — no exception. All ::Channel
# lookups (where + find_by) are stubbed; zero factories, zero DB writes.
#
# Source: app/services/pito/slash/handlers/disconnect.rb
#
# Branches in #call (in priority order):
#   1. parse_target → nil (blank / no second token)    → missing_target_error
#   2. resolve_channel → nil (target present, no match) → not_found_error(target)
#   3. resolve_channel → Channel                        → confirmation_event(channel)
#
# Sub-branches of resolve_channel(target):
#   a. target.start_with?("@")   → strip @, Channel.where("handle LIKE ?", "%frag%").first
#                                    — case-sensitive (@Foo ≠ @foo)
#   b. target.match?(/\A\d+\z/)  → Channel.find_by(id: integer)
#   c. else (bare text)           → Channel.where("handle LIKE ?", "%target%").first
#
# NOTE: The disconnect handler does NOT guard with `return show_help if help?`.
# At the handler level `/disconnect --help` is parsed normally: target = "--help",
# resolve_channel searches LIKE %--help% → nil → not_found error. The dispatcher
# intercepts --help BEFORE constructing the handler (→ HelpBuilder), covered in
# section 9.
#
# All outcomes return Pito::Slash::Result::Ok. Errors are inline events with
# kind: "error" — never Pito::Slash::Result::Error.
RSpec.describe "Dispatch matrix — disconnect (recognition, DB mocked)", type: :dispatch do
  let(:conversation) { double("conversation") }
  let(:channel_double) { double("channel", id: 42, handle: "@gaming", title: "Gaming Channel") }
  let(:confirmation_payload) do
    { "command" => "disconnect", "channel_id" => 42, "body" => "ok", "html" => true }
  end

  # Construct and invoke the handler directly, bypassing the dispatcher.
  # This makes every branch reachable without routing concerns or auth
  # intercepts.  invocation.raw drives parse_target / resolve_channel;
  # args/kwargs are not used by the disconnect handler.
  def call_handler(raw:, authenticated: true)
    invocation = Pito::Slash::Invocation.new(
      verb:   :disconnect,
      args:   [],
      kwargs: {},
      raw:    raw
    )
    Pito::Slash::Handlers::Disconnect.new(invocation:, conversation:, authenticated:).call
  end

  def first_event(raw, authenticated: true)
    call_handler(raw:, authenticated:).events.first
  end

  # Default stubs — overridden per context where needed.
  before do
    # LIKE-based handle lookups return channel_double (found path by default).
    allow(::Channel).to receive(:where).and_return(double("where_rel", first: channel_double))
    # ID-based lookups return nil by default (override per context for found).
    allow(::Channel).to receive(:find_by).and_return(nil)
    # Stub the confirmation builder to avoid all DB (video counts, stats).
    allow(Pito::MessageBuilder::Channel::DisconnectConfirmation).to receive(:call)
      .and_return(confirmation_payload)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 0. Grammar / auth-tier recognition
  #
  # Asserted via parsed_intent (grammar layer only — no handler executed).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "grammar recognition" do
    [
      "/disconnect",
      "/disconnect @gaming",
      "/disconnect gaming",
      "/disconnect 42",
      "/disconnect --help",
      "/disconnect @foo --help"
    ].each do |input|
      it "#{input.inspect} → stack :slash, verb :disconnect, known: true" do
        intent = parsed_intent(input)
        expect(intent[:stack]).to eq(:slash)
        expect(intent[:verb]).to eq(:disconnect)
        expect(intent[:known]).to be(true)
      end
    end

    it "auth tier is :authenticated_only (bare verb)" do
      expect(parsed_intent("/disconnect")[:auth]).to eq(:authenticated_only)
    end

    it "auth tier is :authenticated_only (@handle form)" do
      expect(parsed_intent("/disconnect @gaming")[:auth]).to eq(:authenticated_only)
    end

    it "auth tier is :authenticated_only (numeric id form)" do
      expect(parsed_intent("/disconnect 42")[:auth]).to eq(:authenticated_only)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. Missing target — parse_target returns nil
  #
  # raw.strip.split(/\s+/, 2) has only one element → nil.
  # Outcome: missing_target_error — kind: "error", payload includes "Usage".
  # ═══════════════════════════════════════════════════════════════════════════
  describe "1. missing target (blank arg)" do
    {
      "bare verb"       => "/disconnect",
      "trailing spaces" => "/disconnect   "
    }.each do |label, raw|
      context "#{label} (#{raw.inspect})" do
        it "returns Result::Ok (error is an inline event, not Result::Error)" do
          expect(call_handler(raw:)).to be_a(Pito::Slash::Result::Ok)
        end

        it "emits kind: 'error'" do
          expect(first_event(raw)[:kind]).to eq("error")
        end

        it "payload text includes 'Usage'" do
          expect(first_event(raw)[:payload]["text"]).to include("Usage")
        end

        it "does NOT call DisconnectConfirmation builder" do
          call_handler(raw:)
          expect(Pito::MessageBuilder::Channel::DisconnectConfirmation).not_to have_received(:call)
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. @handle routing — target starts with `@`
  #
  # Fragment = target.delete_prefix("@")
  # Query:   Channel.where("handle LIKE ?", "%#{fragment}%").first
  # Case-sensitive: `@Gaming` and `@gaming` produce different fragments.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "2. @handle routing" do
    # ── 2a. Found ────────────────────────────────────────────────────────────
    describe "2a. found — LIKE returns channel" do
      {
        "@gaming (full match)"                  => "/disconnect @gaming",
        "@gam (partial prefix)"                 => "/disconnect @gam",
        "@G (single-char fragment)"             => "/disconnect @G",
        "@gaming-extra (hyphen in fragment)"    => "/disconnect @gaming-extra"
      }.each do |label, raw|
        context "#{label} (#{raw.inspect})" do
          it "returns Result::Ok" do
            expect(call_handler(raw:)).to be_a(Pito::Slash::Result::Ok)
          end

          it "emits kind: 'confirmation'" do
            expect(first_event(raw)[:kind]).to eq("confirmation")
          end

          it "payload is the DisconnectConfirmation builder output" do
            expect(first_event(raw)[:payload]).to eq(confirmation_payload)
          end
        end
      end

      it "@-only target (/disconnect @) → fragment '' → LIKE %% → matches first channel → confirmation" do
        allow(::Channel).to receive(:where).with("handle LIKE ?", "%%")
          .and_return(double("rel", first: channel_double))
        expect(first_event("/disconnect @")[:kind]).to eq("confirmation")
      end
    end

    # ── 2b. Not found ────────────────────────────────────────────────────────
    describe "2b. not found — LIKE returns nil" do
      before do
        allow(::Channel).to receive(:where).and_return(double("nil_rel", first: nil))
      end

      {
        "@nobody (no match)"                     => "/disconnect @nobody",
        "@MISSING (uppercase, no match)"         => "/disconnect @MISSING",
        "@x-y-z (hyphenated, no match)"          => "/disconnect @x-y-z",
        "@longhandlethatdoesnotexist (no match)" => "/disconnect @longhandlethatdoesnotexist"
      }.each do |label, raw|
        context "#{label} (#{raw.inspect})" do
          it "returns Result::Ok" do
            expect(call_handler(raw:)).to be_a(Pito::Slash::Result::Ok)
          end

          it "emits kind: 'error' (not_found)" do
            expect(first_event(raw)[:kind]).to eq("error")
          end

          it "payload text includes the target (@-prefixed)" do
            target = raw.strip.split(/\s+/, 2).last
            expect(first_event(raw)[:payload]["text"]).to include(target)
          end
        end
      end
    end

    # ── 2c. Case sensitivity ──────────────────────────────────────────────────
    describe "2c. case sensitivity — @Gaming vs @gaming are distinct (no ILIKE)" do
      it "/disconnect @Gaming found (LIKE %Gaming% matches Gaming-cased handle) → confirmation" do
        allow(::Channel).to receive(:where).with("handle LIKE ?", "%Gaming%")
          .and_return(double("found", first: channel_double))
        expect(first_event("/disconnect @Gaming")[:kind]).to eq("confirmation")
      end

      it "/disconnect @gaming not found when handle is @Gaming (wrong case) → error" do
        allow(::Channel).to receive(:where).with("handle LIKE ?", "%gaming%")
          .and_return(double("not_found", first: nil))
        expect(first_event("/disconnect @gaming")[:kind]).to eq("error")
      end

      it "/disconnect @GAMING not found when handle is @gaming (all-caps mismatch) → error" do
        allow(::Channel).to receive(:where).with("handle LIKE ?", "%GAMING%")
          .and_return(double("not_found", first: nil))
        expect(first_event("/disconnect @GAMING")[:kind]).to eq("error")
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. Bare text routing — no @ prefix, non-numeric
  #
  # Same LIKE strategy as @handle but without stripping the @.
  # Query: Channel.where("handle LIKE ?", "%#{target}%").first
  # ═══════════════════════════════════════════════════════════════════════════
  describe "3. bare text routing (no @ prefix, non-numeric)" do
    # ── 3a. Found ────────────────────────────────────────────────────────────
    describe "3a. found — LIKE returns channel" do
      {
        "bare word"        => "/disconnect gaming",
        "partial fragment" => "/disconnect gam",
        "mixed case"       => "/disconnect MyChannel"
      }.each do |label, raw|
        context "#{label} (#{raw.inspect})" do
          it "emits kind: 'confirmation'" do
            expect(first_event(raw)[:kind]).to eq("confirmation")
          end

          it "returns Result::Ok" do
            expect(call_handler(raw:)).to be_a(Pito::Slash::Result::Ok)
          end

          it "payload is the DisconnectConfirmation builder output" do
            expect(first_event(raw)[:payload]).to eq(confirmation_payload)
          end
        end
      end
    end

    # ── 3b. Not found ────────────────────────────────────────────────────────
    describe "3b. not found — LIKE returns nil" do
      before do
        allow(::Channel).to receive(:where).and_return(double("nil_rel", first: nil))
      end

      {
        "bare nonsense" => "/disconnect xyzzy",
        "bare missing"  => "/disconnect nobody"
      }.each do |label, raw|
        context "#{label} (#{raw.inspect})" do
          it "emits kind: 'error' (not_found)" do
            expect(first_event(raw)[:kind]).to eq("error")
          end

          it "payload text includes the bare target" do
            target = raw.strip.split(/\s+/, 2).last
            expect(first_event(raw)[:payload]["text"]).to include(target)
          end
        end
      end
    end

    # ── 3c. Multi-word target ─────────────────────────────────────────────────
    describe "3c. multi-word target (entire rest of raw becomes the LIKE fragment)" do
      it "/disconnect foo bar → target 'foo bar' → LIKE %foo bar% → not_found → error" do
        allow(::Channel).to receive(:where).with("handle LIKE ?", "%foo bar%")
          .and_return(double("nil_rel", first: nil))
        expect(first_event("/disconnect foo bar")[:kind]).to eq("error")
      end

      it "/disconnect foo bar → not-found payload includes the full 'foo bar' target" do
        allow(::Channel).to receive(:where).and_return(double("nil_rel", first: nil))
        expect(first_event("/disconnect foo bar")[:payload]["text"]).to include("foo bar")
      end

      it "/disconnect foo bar → found if LIKE matches → confirmation" do
        allow(::Channel).to receive(:where).with("handle LIKE ?", "%foo bar%")
          .and_return(double("found", first: channel_double))
        expect(first_event("/disconnect foo bar")[:kind]).to eq("confirmation")
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 4. Numeric ID routing — all-digit target → find_by(id: integer)
  #
  # The LIKE path is NOT taken; exact find_by is used instead.
  # id 0 is never valid (find_by returns nil for id 0 in any real DB).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "4. numeric ID routing" do
    # ── 4a. Found ────────────────────────────────────────────────────────────
    describe "4a. found — find_by returns channel" do
      [ 1, 42, 999 ].each do |id|
        context "id #{id}" do
          before do
            allow(::Channel).to receive(:find_by).with(id: id).and_return(channel_double)
          end

          it "/disconnect #{id} → kind: 'confirmation'" do
            expect(first_event("/disconnect #{id}")[:kind]).to eq("confirmation")
          end

          it "/disconnect #{id} → returns Result::Ok" do
            expect(call_handler(raw: "/disconnect #{id}")).to be_a(Pito::Slash::Result::Ok)
          end

          it "/disconnect #{id} → payload is the DisconnectConfirmation builder output" do
            expect(first_event("/disconnect #{id}")[:payload]).to eq(confirmation_payload)
          end
        end
      end
    end

    # ── 4b. Not found ─────────────────────────────────────────────────────────
    describe "4b. not found — find_by returns nil" do
      before do
        allow(::Channel).to receive(:find_by).and_return(nil)
      end

      [ 99999, 12345 ].each do |id|
        context "id #{id} (not found)" do
          it "/disconnect #{id} → kind: 'error' (not_found)" do
            expect(first_event("/disconnect #{id}")[:kind]).to eq("error")
          end

          it "/disconnect #{id} → payload includes '#{id}'" do
            expect(first_event("/disconnect #{id}")[:payload]["text"]).to include(id.to_s)
          end

          it "/disconnect #{id} → returns Result::Ok (inline error)" do
            expect(call_handler(raw: "/disconnect #{id}")).to be_a(Pito::Slash::Result::Ok)
          end
        end
      end
    end

    it "/disconnect 0 (never-valid id) → error (find_by(id: 0) returns nil)" do
      allow(::Channel).to receive(:find_by).with(id: 0).and_return(nil)
      expect(first_event("/disconnect 0")[:kind]).to eq("error")
    end

    it "all-digit target routes via find_by, NOT the LIKE path" do
      allow(::Channel).to receive(:find_by).with(id: 42).and_return(channel_double)
      expect(::Channel).not_to receive(:where)
      call_handler(raw: "/disconnect 42")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 5. Whitespace normalisation in parse_target
  #
  # raw.strip is called first; then split(/\s+/, 2) — any whitespace run is
  # treated as a single separator. Trailing spaces after the target are stripped
  # by .strip on parts.last.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "5. whitespace normalisation" do
    it "double space before @handle → same as single space → confirmation" do
      expect(first_event("/disconnect  @gaming")[:kind]).to eq("confirmation")
    end

    it "trailing spaces after @handle → stripped → same channel lookup → confirmation" do
      expect(first_event("/disconnect @gaming   ")[:kind]).to eq("confirmation")
    end

    it "tab between verb and @handle → treated as whitespace separator → confirmation" do
      expect(first_event("/disconnect\t@gaming")[:kind]).to eq("confirmation")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 6. --help at handler level (handler does NOT call help? / show_help)
  #
  # Unlike /rename, the disconnect handler has no `return show_help if help?`
  # guard in #call. A raw like `/disconnect --help` is parsed normally:
  #   target = "--help" (or "@gaming --help" for combined inputs)
  #   resolve_channel("--help") → LIKE %--help% → nil → not_found error.
  # The dispatcher's own --help intercept is covered separately in section 9.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "6. --help at handler level (treated as a target string, not a flag)" do
    before do
      allow(::Channel).to receive(:where).and_return(double("nil_rel", first: nil))
    end

    it "/disconnect --help → target '--help' → not_found error (NOT a help page)" do
      expect(first_event("/disconnect --help")[:kind]).to eq("error")
    end

    it "/disconnect --help → payload includes '--help' (target echoed)" do
      expect(first_event("/disconnect --help")[:payload]["text"]).to include("--help")
    end

    it "/disconnect @gaming --help → target '@gaming --help' (entire rest) → LIKE %gaming --help% → error" do
      # parse_target splits on first whitespace only; rest = "@gaming --help"
      # starts with @ → fragment = "gaming --help" → LIKE %gaming --help%
      allow(::Channel).to receive(:where).with("handle LIKE ?", "%gaming --help%")
        .and_return(double("nil_rel", first: nil))
      expect(first_event("/disconnect @gaming --help")[:kind]).to eq("error")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 7. Auth parameter — handler does NOT gate on `authenticated`
  #
  # Grammar declares :authenticated_only; the external gate lives in the job.
  # Calling the handler directly with authenticated: false processes identically
  # to authenticated: true — all branches behave the same.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "7. auth parameter (handler does not gate)" do
    it "authenticated: false + missing target → kind: 'error' (missing_target), not auth rejection" do
      expect(first_event("/disconnect", authenticated: false)[:kind]).to eq("error")
    end

    it "authenticated: false + missing target → returns Result::Ok (not Result::Error)" do
      expect(call_handler(raw: "/disconnect", authenticated: false)).to be_a(Pito::Slash::Result::Ok)
    end

    it "authenticated: false + @handle found → kind: 'confirmation' (auth flag ignored by handler)" do
      expect(first_event("/disconnect @gaming", authenticated: false)[:kind]).to eq("confirmation")
    end

    it "authenticated: false + @handle not found → kind: 'error' (not_found, not auth)" do
      allow(::Channel).to receive(:where).and_return(double("nil_rel", first: nil))
      expect(first_event("/disconnect @nobody", authenticated: false)[:kind]).to eq("error")
    end

    it "authenticated: false + numeric id found → kind: 'confirmation'" do
      allow(::Channel).to receive(:find_by).with(id: 42).and_return(channel_double)
      expect(first_event("/disconnect 42", authenticated: false)[:kind]).to eq("confirmation")
    end

    it "authenticated: false + numeric id not found → kind: 'error'" do
      expect(first_event("/disconnect 99999", authenticated: false)[:kind]).to eq("error")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 8. Result::Ok invariant — all branches return Result::Ok
  #
  # Errors are inline kind: "error" events inside Result::Ok.events,
  # never Pito::Slash::Result::Error (which is caught at controller level).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "8. Result::Ok invariant across all branches" do
    it "missing-target path returns Result::Ok" do
      expect(call_handler(raw: "/disconnect")).to be_a(Pito::Slash::Result::Ok)
    end

    it "found path (@handle) returns Result::Ok" do
      expect(call_handler(raw: "/disconnect @gaming")).to be_a(Pito::Slash::Result::Ok)
    end

    it "not-found path (@handle) returns Result::Ok" do
      allow(::Channel).to receive(:where).and_return(double("nil_rel", first: nil))
      expect(call_handler(raw: "/disconnect @nobody")).to be_a(Pito::Slash::Result::Ok)
    end

    it "found path (bare text) returns Result::Ok" do
      expect(call_handler(raw: "/disconnect gaming")).to be_a(Pito::Slash::Result::Ok)
    end

    it "not-found path (bare text) returns Result::Ok" do
      allow(::Channel).to receive(:where).and_return(double("nil_rel", first: nil))
      expect(call_handler(raw: "/disconnect nobody")).to be_a(Pito::Slash::Result::Ok)
    end

    it "found path (numeric id) returns Result::Ok" do
      allow(::Channel).to receive(:find_by).with(id: 42).and_return(channel_double)
      expect(call_handler(raw: "/disconnect 42")).to be_a(Pito::Slash::Result::Ok)
    end

    it "not-found path (numeric id) returns Result::Ok" do
      expect(call_handler(raw: "/disconnect 99999")).to be_a(Pito::Slash::Result::Ok)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 9. Dispatcher-level --help / -h intercept
  #
  # The dispatcher intercepts --help before constructing the handler, routing
  # to Pito::Slash::HelpBuilder. The handler's #call is never invoked.
  #
  # Dispatcher regex: /\s--help\b|\s-h\b/ — leading \s is required.
  # So `/disconnect--help` (no space) does NOT trigger the intercept.
  # HelpBuilder is stubbed to avoid I18n rendering and any DB dependency.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "9. dispatcher --help / -h intercept" do
    let(:help_result) do
      Pito::Slash::Result::Ok.new(events: [ { kind: "system", payload: { text: "help" } } ])
    end

    def dispatch(raw)
      Pito::Slash::Dispatcher.call(input: raw, conversation:, authenticated: true)
    end

    before do
      allow(Pito::Slash::HelpBuilder).to receive(:call).and_return(help_result)
    end

    {
      "bare --help"         => "/disconnect --help",
      "@handle + --help"    => "/disconnect @gaming --help",
      "numeric id + --help" => "/disconnect 42 --help",
      "short -h flag"       => "/disconnect -h",
      "@handle + -h"        => "/disconnect @gaming -h"
    }.each do |label, raw|
      context "#{label} (#{raw.inspect})" do
        it "calls HelpBuilder (handler bypassed)" do
          expect(Pito::Slash::HelpBuilder).to receive(:call)
          dispatch(raw)
        end

        it "DisconnectConfirmation builder is never called" do
          expect(Pito::MessageBuilder::Channel::DisconnectConfirmation).not_to receive(:call)
          dispatch(raw)
        end
      end
    end

    it "no leading space: /disconnect--help → HelpBuilder NOT called (regex requires \\s)" do
      # The lexer may tokenize this as verb 'disconnect--help', producing an unknown-verb
      # Result::Error — either way, HelpBuilder is never reached.
      dispatch("/disconnect--help")
      expect(Pito::Slash::HelpBuilder).not_to have_received(:call)
    end
  end
end
