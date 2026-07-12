# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/login` + `/authenticate` (grammar + masking only) ───────
#
# RULE: every kwarg combination the grammar recognises — no exception.
# Zero factories, zero DB writes. Pito::Auth::ChatLogin is NEVER called.
#
# `/login` is a handler-less slash command (grammar spec: aliases [:authenticate],
# auth: :unauthenticated_only, one free :code slot, no handler class in the
# Slash::Registry). The controller intercepts it synchronously via
# Pito::InputMasking.login_command? → handle_login. The Dispatcher is never
# involved in a real login flow.
#
# This spec asserts two layers only:
#   1. Grammar / recognition — parsed_intent (shape + registry alias lookup).
#   2. Masking             — Pito::InputMasking (login_command?, mask_secret,
#                            for_history).
RSpec.describe "Dispatch matrix — /login + /authenticate (recognition + masking)", type: :dispatch do
  # ═══════════════════════════════════════════════════════════════════════════
  # 0. Grammar recognition via parsed_intent
  #
  # slash_intent downcases the token before the registry lookup, so every case
  # variant of both the canonical verb (:login) and its :authenticate alias
  # resolves identically: verb :login, auth :unauthenticated_only, known true.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "grammar recognition" do
    # ── 0a. Full recognition (stack + verb + auth + known) ──────────────────
    [
      # canonical verb with 6-digit TOTP code
      "/login 123456",
      # alias with code
      "/authenticate 123456",
      # bare (no code) — free slot; not enforced at the grammar registry level
      "/login",
      "/authenticate",
      # case variants — slash_intent .downcase before registry lookup
      "/LOGIN 123456",
      "/AUTHENTICATE 123456",
      "/Login 123456",
      "/Authenticate 123456",
      "/LoGiN 123456",
      "/aUtHeNtIcAtE 123456",
      # leading whitespace — parsed_intent strips before routing
      "  /login 123456",
      "  /authenticate 123456",
      # tab separator — split(/\s+/) handles internal whitespace
      "/login\t123456"
    ].each do |input|
      it "#{input.inspect} → stack :slash, verb :login, auth :unauthenticated_only, known: true" do
        intent = parsed_intent(input)
        expect(intent[:stack]).to eq(:slash)
        expect(intent[:tool]).to eq(:login)
        expect(intent[:auth]).to eq(:unauthenticated_only)
        expect(intent[:known]).to be(true)
      end
    end

    # ── 0b. Token field (always downcased by slash_intent) ──────────────────
    it "token is 'login' for /login 123456" do
      expect(parsed_intent("/login 123456")[:token]).to eq("login")
    end

    it "token is 'authenticate' for /authenticate 123456" do
      expect(parsed_intent("/authenticate 123456")[:token]).to eq("authenticate")
    end

    it "token is downcased to 'login' for /LOGIN 123456" do
      expect(parsed_intent("/LOGIN 123456")[:token]).to eq("login")
    end

    it "token is downcased to 'authenticate' for /AUTHENTICATE 123456" do
      expect(parsed_intent("/AUTHENTICATE 123456")[:token]).to eq("authenticate")
    end

    # ── 0c. Auth tier exclusivity ────────────────────────────────────────────
    it "auth tier is :unauthenticated_only, NOT :authenticated_only" do
      expect(parsed_intent("/login 123456")[:auth]).not_to eq(:authenticated_only)
    end

    it "contrast — /logout carries :authenticated_only (opposite tier)" do
      expect(parsed_intent("/logout")[:auth]).to eq(:authenticated_only)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. No false positives — similar slash commands are NOT :login
  # ═══════════════════════════════════════════════════════════════════════════
  describe "no false positives from similar verbs" do
    {
      "/logout"  => :logout,
      "/connect" => :connect,
      "/new"     => :new,
      "/resume"  => :resume
    }.each do |input, expected_verb|
      it "#{input} resolves to :#{expected_verb}, NOT :login" do
        intent = parsed_intent(input)
        expect(intent[:tool]).to eq(expected_verb)
        expect(intent[:tool]).not_to eq(:login)
      end
    end

    it "'login 123456' (missing /) routes to :chat stack, not :slash" do
      expect(parsed_intent("login 123456")[:stack]).to eq(:chat)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. Pito::InputMasking.login_command?
  #
  # Regex: /\A\/(?:login|authenticate)(\s|\z)/i — verb-bounded, case-insensitive.
  # Matches /login and /authenticate (with trailing space OR end-of-string);
  # rejects any suffix that would extend the verb (/loginx, /login_extra).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "Pito::InputMasking.login_command?" do
    def lc?(str) = Pito::InputMasking.login_command?(str)

    # ── 2a. Returns true ─────────────────────────────────────────────────────
    {
      "/login 123456"        => "canonical /login with code",
      "/authenticate 123456" => "canonical /authenticate with code",
      "/login"               => "bare /login (\\z anchor matches end-of-string)",
      "/authenticate"        => "bare /authenticate",
      "/LOGIN 123456"        => "uppercase /LOGIN (i flag)",
      "/AUTHENTICATE 123456" => "uppercase /AUTHENTICATE",
      "/Login 123456"        => "title-case /Login",
      "/Authenticate 123456" => "title-case /Authenticate",
      "/LoGiN 123456"        => "mixed-case /LoGiN",
      "  /login 123456"      => "leading whitespace (input.to_s.strip before match)",
      "/login\t123456"       => "tab separator (\\s in regex matches \\t)"
    }.each do |input, label|
      it "true  — #{label}" do
        expect(lc?(input)).to be(true)
      end
    end

    # ── 2b. Returns false ────────────────────────────────────────────────────
    {
      "/logout"          => "/logout — different verb",
      "/loginx"          => "/loginx — suffix 'x' not \\s|\\z (verb-bounded)",
      "/login_extra"     => "/login_extra — underscore is not \\s",
      "/authenticatex"   => "/authenticatex — suffix after verb",
      "login 123456"     => "missing leading / (\\A/ not matched)",
      "/log in 123456"   => "spaced-out verb /log in",
      ""                 => "empty string"
    }.each do |input, label|
      it "false — #{label}" do
        expect(lc?(input)).to be(false)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. Pito::InputMasking.mask_secret
  #
  # Splits on first whitespace group (limit 2), returns input unchanged when
  # there is no rest (bare form), otherwise returns "#{verb} #{'*' * rest.length}".
  # Verb casing is preserved (no downcase). Mask length is proportional.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "Pito::InputMasking.mask_secret" do
    def ms(str) = Pito::InputMasking.mask_secret(str)

    it "/login 123456 → /login ******  (6 stars for 6-char code)" do
      expect(ms("/login 123456")).to eq("/login ******")
    end

    it "/authenticate 123456 → /authenticate ******" do
      expect(ms("/authenticate 123456")).to eq("/authenticate ******")
    end

    it "mask length = rest.length — 8-char code yields 8 stars" do
      expect(ms("/login 12345678")).to eq("/login ********")
    end

    it "mask length = rest.length — 7-char code yields 7 stars" do
      expect(ms("/authenticate 9999999")).to eq("/authenticate *******")
    end

    it "non-numeric rest is masked length-proportionally" do
      # "notanumber" = 10 chars → 10 stars
      expect(ms("/login notanumber")).to eq("/login **********")
    end

    it "bare /login (no code) → returned unchanged (rest.blank? guard)" do
      expect(ms("/login")).to eq("/login")
    end

    it "bare /authenticate (no code) → returned unchanged" do
      expect(ms("/authenticate")).to eq("/authenticate")
    end

    it "preserves verb casing — /LOGIN 123456 → /LOGIN ******" do
      expect(ms("/LOGIN 123456")).to eq("/LOGIN ******")
    end

    it "preserves alias casing — /AUTHENTICATE 123456 → /AUTHENTICATE ******" do
      expect(ms("/AUTHENTICATE 123456")).to eq("/AUTHENTICATE ******")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 4. Pito::InputMasking.for_history
  #
  # Dispatch priority: config_command? → login_command? → verbatim.
  # /login never reaches the config branch. The masked form stored in turns
  # exposes only the verb, never the TOTP code.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "Pito::InputMasking.for_history" do
    def fh(str) = Pito::InputMasking.for_history(str)

    it "/login 123456 → /login ******" do
      expect(fh("/login 123456")).to eq("/login ******")
    end

    it "/authenticate 123456 → /authenticate ******" do
      expect(fh("/authenticate 123456")).to eq("/authenticate ******")
    end

    it "bare /login (no code) → /login verbatim" do
      expect(fh("/login")).to eq("/login")
    end

    it "bare /authenticate (no code) → /authenticate verbatim" do
      expect(fh("/authenticate")).to eq("/authenticate")
    end

    it "/LOGIN 123456 (uppercase) → /LOGIN ******" do
      expect(fh("/LOGIN 123456")).to eq("/LOGIN ******")
    end

    it "/AUTHENTICATE 123456 (uppercase alias) → /AUTHENTICATE ******" do
      expect(fh("/AUTHENTICATE 123456")).to eq("/AUTHENTICATE ******")
    end

    it "/logout is NOT a login command → returned verbatim" do
      expect(fh("/logout")).to eq("/logout")
    end

    it "plain chat input is returned verbatim" do
      expect(fh("list games")).to eq("list games")
    end

    it "/config credential command routes through config branch, NOT login branch" do
      # for_history checks config_command? FIRST — /config never reaches login_command?
      result = fh("/config google client_id=abc client_secret=xyz")
      expect(result).to include("client_id=***")
      expect(result).not_to include("client_id=abc")
    end
  end
end
