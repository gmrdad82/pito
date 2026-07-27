# frozen_string_literal: true

module Pito
  module Keybinding
    # Maps a keyboard-shortcut label to its display form — the web twin of
    # pito-tui's KeyGlyph (internal/ui/render/keyglyph.go in
    # gmrdad82/pito-tui): modifiers and named keys are spelled out as WORDS,
    # and only the arrows stay glyphs (T8, full reversal of decision 11,
    # owner 2026-07-25 — see MODIFIER_GLYPHS). Pure and
    # idempotent: feeding it its own output (or any already-mapped input)
    # returns that input unchanged, and anything that doesn't cleanly parse
    # as a modifier+key chord — product words, digits, slash-commands,
    # prose — passes through untouched rather than being mangled.
    #
    # Convention (owner 2026-07-24, REVERSED IN TWO STAGES 2026-07-25 — T8):
    # shift became the word "shift+" first (⇧ was rejected on legibility
    # grounds — it is just an up-arrow that happens to mean shift). An
    # interim ruling kept ⌃ as a glyph ("I like ^c" — decades of terminal
    # convention already read "^C" as ctrl); the owner then reversed that
    # too — "then lets revert the and use ctrl+r and so on" — so ctrl is
    # now the word "ctrl+" as well, and ␣ space / ⇥ tab joined the words
    # with it. Only ↑↓←→ stay glyphs: they have no compact word form and
    # read fine. NEVER ⌘/cmd — the Mac cmd-swap DISPLAY is retired app-wide
    # (functional Mac Cmd input is a separate concern and still works where
    # it did). Single letters stay LOWERCASE (ctrl+k not ctrl+K);
    # Esc/Home/End/PgUp/PgDn/Enter stay Title-case WORDS (their Unicode
    # glyphs tofu in most terminals/browsers). `+`/`-` separators are both
    # accepted on the way in; each modifier's display form carries its own
    # "+", so it is written straight onto the key with no extra join
    # character.
    #
    # `Pito::Keybinding::ShortcutComponent#call` routes every `keys:` value
    # through this before rendering, so every ShortcutComponent/HintComponent
    # call site gets the convention for free. Call sites that render a raw
    # shortcut span WITHOUT going through ShortcutComponent (a static
    # `<template>` clone, a locale-sourced help-table key) call `.format`
    # directly.
    module Glyph
      # Modifier word (lowercased) → display form. Only ctrl and shift
      # exist in this app — no cmd/meta/alt. Both are spelled out, and each
      # display form carries its own "+" separator (see split_modifier).
      MODIFIER_GLYPHS = {
        "ctrl"  => "ctrl+",
        "shift" => "shift+"
      }.freeze

      # Named key word (lowercased) → display form. Every named key is a
      # WORD; only the four arrows stay glyphs.
      NAMED_KEY_GLYPHS = {
        "space"  => "space",
        "tab"    => "tab",
        "enter"  => "Enter",
        "return" => "Enter",
        "esc"    => "Esc",
        "home"   => "Home",
        "end"    => "End",
        "pgup"   => "PgUp",
        "pgdn"   => "PgDn",
        "pgdown" => "PgDn",
        "up"     => "↑",
        "down"   => "↓",
        "left"   => "←",
        "right"  => "→"
      }.freeze

      # Arrows are the only glyphs this module still produces, so they are
      # recognized as already-mapped: re-parsing its own output (idempotency)
      # or a hand-authored bare arrow pair ("↑/↓") round-trips unchanged.
      ALREADY_GLYPH_TOKENS = %w[↑ ↓ ← →].freeze

      # Pre-reversal output some caller might still be holding. Fold these to
      # the current word form rather than passing a retired glyph through.
      LEGACY_GLYPH_TOKENS = {
        "␣" => "space",
        "⇥" => "tab"
      }.freeze

      class << self
        # Format a single shortcut label. Never raises — an unparseable
        # input is returned unchanged (see module doc).
        def format(value)
          s = value.to_s
          return s if s.empty?

          mod, rest = split_modifier(s)
          key_part = mod ? rest : s

          # A lone "/" is the literal slash key, not a two-part join separator.
          return mod ? "#{mod}/" : s if key_part == "/"

          if key_part.include?("/")
            mapped = key_part.split("/", -1).map { |token| map_token(token) }
            return s if mapped.any?(&:nil?)

            joined = mapped.join("/")
            return mod ? "#{mod}#{joined}" : joined
          end

          glyph = map_token(key_part)
          return s if glyph.nil?

          mod ? "#{mod}#{glyph}" : glyph
        end

        private

        # Looks for a leading ctrl/shift modifier and returns its display
        # form plus the remainder of s. Accepts a word followed by a '+' or
        # '-' separator ("ctrl+c", "ctrl-c", "shift+r") — the shape `format`
        # itself now produces, so re-parsing its own output is idempotent —
        # or a legacy "⌃"/"⇧" glyph with no separator, the pre-reversal
        # output some caller might still be holding, which normalizes to the
        # spelled-out word rather than being rejected: degrade gracefully,
        # never mangle an input this module used to produce itself. Returns
        # [nil, nil] when no modifier is present.
        def split_modifier(s)
          lower = s.downcase
          MODIFIER_GLYPHS.each do |word, disp|
            next unless lower.start_with?(word)

            i = word.length
            next if i >= s.length

            sep = s[i]
            return [ disp, s[(i + 1)..] ] if sep == "+" || sep == "-"
          end

          case s[0]
          when "⌃" then return [ "ctrl+", s[1..] ]
          when "⇧" then return [ "shift+", s[1..] ]
          end

          [ nil, nil ]
        end

        # Maps a single key token (one side of a "/"-joined pair, or the
        # whole key-part) to its glyph form. Returns nil when the token
        # doesn't parse as a single letter or a recognized named key.
        def map_token(token)
          return nil if token.nil? || token.empty?

          lower = token.downcase
          return NAMED_KEY_GLYPHS[lower] if NAMED_KEY_GLYPHS.key?(lower)
          return token if ALREADY_GLYPH_TOKENS.include?(token)
          return LEGACY_GLYPH_TOKENS[token] if LEGACY_GLYPH_TOKENS.key?(token)

          letter_glyph(token)
        end

        # A single-letter token maps to its plain lowercase form. Accepts an
        # uppercase letter too (folds to the same result) for idempotency
        # and leniency.
        def letter_glyph(token)
          return nil unless token.length == 1
          return token.downcase if token.match?(/\A[A-Za-z]\z/)

          nil
        end
      end
    end
  end
end
