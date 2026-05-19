require "rails_helper"

# 2026-05-17 polish — game cover thumbnail border.
#
# Locks the new `--color-cover-border` token + the single rule that
# applies it to every cover surface on `/games`:
#
#   * `Games::CoverComponent`           via `.game-cover-img`
#   * rich tile (games + bundles)       via `.tile-cover img`
#
# (The collection composite tile was retired alongside the Collection
# model drop; the bundle composite tile takes its place and is locked
# by its own selector elsewhere in the stylesheet.)
#
# Tone is intentionally OPPOSITE to the page background — dark hairline
# on the light theme, light hairline on the dark theme — so the cover
# art reads as a framed thumbnail at every shelf size. Distinct from
# `--color-border` (a same-tone hairline used for tables, inputs, and
# dividers).
#
# A blunt source-string check is enough — these are intentional tokens
# and selectors; a future rename should update both the spec and the
# stylesheet together.
RSpec.describe "application.css — 2026-05-17 cover thumbnail border", type: :asset do
  let(:css_path) { Rails.root.join("app/assets/tailwind/application.css") }
  let(:css) { File.read(css_path) }

  describe "--color-cover-border token (opposite-tone, per-theme)" do
    it "declares `--color-cover-border` exactly twice (one per theme scope)" do
      expect(css.scan(/^\s*--color-cover-border:/m).length).to eq(2)
    end

    it "pins the light-theme value to #1a1a1a (dark hairline on light bg)" do
      expect(css).to match(/--color-cover-border:\s*#1a1a1a/)
    end

    it "pins the dark-theme value to #aaaaaa (light hairline on dark bg)" do
      expect(css).to match(/--color-cover-border:\s*#aaaaaa/)
    end
  end

  describe "1px border rule applied to every cover surface" do
    it "declares the combined `.game-cover-img, .tile-cover img` rule" do
      # Single selector list with both hooks; allow whitespace
      # variation but lock the order so the rationale comment above the
      # rule stays accurate. Additional selectors (bundle composite,
      # pane-row narrow cover) may follow on subsequent lines of the
      # same selector list — we anchor on the leading pair.
      expect(css).to match(
        /\.game-cover-img,\s*\.tile-cover\s+img[\s,]/
      )
    end

    it "the rule body is exactly `border: 1px solid var(--color-cover-border)`" do
      # Capture the body of the combined selector starting at
      # `.game-cover-img,\n.tile-cover img` and assert the border
      # declaration sits inside it (and that no second `border:` line
      # has crept in).
      body = css[
        /\.game-cover-img,\s*\.tile-cover\s+img[^{]*\{([^}]*)\}/m,
        1
      ]
      expect(body).not_to be_nil
      expect(body).to match(/border:\s*1px\s+solid\s+var\(--color-cover-border\)\s*;/)
      expect(body.scan(/^\s*border\s*:/m).length).to eq(1)
    end
  end
end
