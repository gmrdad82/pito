# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Themes::Contrast do
  # ── (a) Math unit tests ───────────────────────────────────────────────────

  describe ".relative_luminance" do
    it "returns ~1.0 for white" do
      expect(described_class.relative_luminance("#ffffff")).to be_within(0.001).of(1.0)
    end

    it "returns ~0.0 for black" do
      expect(described_class.relative_luminance("#000000")).to be_within(0.001).of(0.0)
    end
  end

  describe ".ratio" do
    it "black/white is ~21.0" do
      expect(described_class.ratio("#000000", "#ffffff")).to be_within(0.01).of(21.0)
    end

    it "identical colours return 1.0" do
      expect(described_class.ratio("#777777", "#777777")).to eq(1.0)
    end

    it "is commutative (order of arguments does not matter)" do
      expect(described_class.ratio("#5170ff", "#1a1b26")).to \
        be_within(0.001).of(described_class.ratio("#1a1b26", "#5170ff"))
    end

    it "brand_pito vs tokyo-night bg_root is ~4.16 (within ±0.05)" do
      # sanity: the default-theme logo contrast is comfortable
      expect(described_class.ratio("#5170ff", "#1a1b26")).to be_within(0.05).of(4.16)
    end
  end

  # ── (b) Regression guard ──────────────────────────────────────────────────
  #
  # ACCEPTED_LOW_CONTRAST is the hand-verified snapshot of every pair that
  # currently fails the enforced 3.0:1 floor.  It is intentionally explicit
  # so that:
  #   • a NEW failure added by a theme change causes the spec to fail loudly,
  #   • a FIXED pair that is accidentally left in the list is also detected
  #     (staleness guard below), keeping the list honest.
  #
  # Format: "slug:token:bg"  — sorted alphabetically.
  #
  # Two groups:
  #   brand_pito:*:bg_surface  — pito blue kept as-is (faint but legible
  #                              border, never invisible); see findings doc.
  #   everything else          — to fix via adaptive accent / fg_dim tuning
  #                              (light: darken accents; dark: nudge
  #                               nord/solarized-dark).
  #
  # To accept a new regression, add its key here WITH a comment explaining why.
  # To mark something fixed, remove its key (the staleness guard will remind
  # you if you forget).
  ACCEPTED_LOW_CONTRAST = Set.new([
    # ── brand_pito:*:bg_surface ───────────────────────────────────────────────
    # intentionally accepted — pito blue kept as-is (faint but legible border,
    # never invisible)
    "catppuccin-latte:brand_pito:bg_surface",
    "dracula:brand_pito:bg_surface",
    "gruvbox-dark:brand_pito:bg_surface",
    "gruvbox-light:brand_pito:bg_surface",
    "nord:brand_pito:bg_surface",

    # ── to fix via adaptive accent / fg_dim tuning ───────────────────────────
    # (light: darken accents; dark: nudge nord/solarized-dark)

    # ayu-light: nearly all accents too bright on pale background; fg_dim washed out
    "ayu-light:accent_cyan:bg_root",
    "ayu-light:accent_cyan:bg_surface",
    "ayu-light:accent_green:bg_root",
    "ayu-light:accent_green:bg_surface",
    "ayu-light:accent_orange:bg_root",
    "ayu-light:accent_orange:bg_surface",
    "ayu-light:accent_red:bg_root",
    "ayu-light:accent_red:bg_surface",
    "ayu-light:accent_yellow:bg_root",
    "ayu-light:accent_yellow:bg_surface",
    "ayu-light:fg_dim:bg_root",
    "ayu-light:fg_dim:bg_surface",

    # catppuccin-latte: bright palette fails on light bg
    "catppuccin-latte:accent_cyan:bg_surface",
    "catppuccin-latte:accent_green:bg_root",
    "catppuccin-latte:accent_green:bg_surface",
    "catppuccin-latte:accent_orange:bg_root",
    "catppuccin-latte:accent_orange:bg_surface",
    "catppuccin-latte:accent_yellow:bg_root",
    "catppuccin-latte:accent_yellow:bg_surface",

    # dracula: fg_dim dips on surface
    "dracula:fg_dim:bg_surface",

    # gruvbox-light: warm palette; accents too light
    "gruvbox-light:accent_cyan:bg_root",
    "gruvbox-light:accent_cyan:bg_surface",
    "gruvbox-light:accent_green:bg_root",
    "gruvbox-light:accent_green:bg_surface",
    "gruvbox-light:accent_orange:bg_surface",
    "gruvbox-light:accent_yellow:bg_root",
    "gruvbox-light:accent_yellow:bg_surface",
    "gruvbox-light:fg_dim:bg_surface",

    # nord: accent_red muted; fg_dim blend low
    "nord:accent_red:bg_surface",

    # one-light: accent_green and accent_yellow dip on surface
    "one-light:accent_green:bg_surface",
    "one-light:accent_yellow:bg_surface",

    # solarized-dark: low-contrast by design; orange/purple/red + fg_dim fail
    "solarized-dark:accent_orange:bg_surface",
    "solarized-dark:accent_purple:bg_surface",
    "solarized-dark:accent_red:bg_surface",
    "solarized-dark:fg_dim:bg_root",
    "solarized-dark:fg_dim:bg_surface",

    # solarized-light: low-contrast by design; most accents + fg_dim fail
    "solarized-light:accent_cyan:bg_root",
    "solarized-light:accent_cyan:bg_surface",
    "solarized-light:accent_green:bg_root",
    "solarized-light:accent_green:bg_surface",
    "solarized-light:accent_yellow:bg_root",
    "solarized-light:accent_yellow:bg_surface",
    "solarized-light:fg_dim:bg_root",
    "solarized-light:fg_dim:bg_surface",

    # tokyo-night: fg_dim is the known problem token
    "tokyo-night:fg_dim:bg_root",
    "tokyo-night:fg_dim:bg_surface",

    # tomorrow: several accents too bright on near-white bg
    "tomorrow:accent_cyan:bg_surface",
    "tomorrow:accent_orange:bg_root",
    "tomorrow:accent_orange:bg_surface",
    "tomorrow:accent_yellow:bg_root",
    "tomorrow:accent_yellow:bg_surface",
    "tomorrow:fg_dim:bg_surface"
  ]).freeze

  describe "regression guard" do
    subject(:all_failures) { described_class.audit_all }

    let(:failure_keys) do
      all_failures.map { |f| "#{f.slug}:#{f.token}:#{f.bg}" }.to_set
    end

    it "produces no NEW failures outside the accepted allowlist" do
      new_failures = failure_keys - ACCEPTED_LOW_CONTRAST
      expect(new_failures).to be_empty, lambda {
        lines = all_failures
          .select { |f| new_failures.include?("#{f.slug}:#{f.token}:#{f.bg}") }
          .map { |f| "  #{f.slug}:#{f.token}:#{f.bg}  ratio=#{f.ratio} (target #{f.target})" }
        "New contrast failures not in ACCEPTED_LOW_CONTRAST:\n#{lines.join("\n")}\n" \
          "Add the key(s) to ACCEPTED_LOW_CONTRAST with a comment, or fix the theme."
      }
    end

    it "has no stale entries in ACCEPTED_LOW_CONTRAST (pairs that now pass)" do
      stale = ACCEPTED_LOW_CONTRAST - failure_keys
      expect(stale).to be_empty, lambda {
        "Stale allowlist entries (now passing — remove them):\n" \
          "#{stale.sort.map { |k| "  #{k}" }.join("\n")}"
      }
    end
  end

  # ── (c) Sanity: token coverage ────────────────────────────────────────────

  describe "token coverage sanity" do
    let(:all_tokens) do
      (described_class::TEXT_TOKENS +
       described_class::BRAND_TOKENS +
       described_class::BG_TOKENS).uniq
    end

    it "Registry.all is non-empty" do
      expect(Pito::Themes::Registry.all).not_to be_empty
    end

    it "every audited token key exists in each definition.tokens" do
      missing = []
      Pito::Themes::Registry.all.each do |defn|
        all_tokens.each do |tok|
          missing << "#{defn.slug}:#{tok}" unless defn.tokens.key?(tok)
        end
      end
      expect(missing).to be_empty,
        "Token keys missing from definition.tokens:\n#{missing.map { |k| "  #{k}" }.join("\n")}"
    end
  end
end
