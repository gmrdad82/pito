require "rails_helper"

# 2026-05-19 — Games::BundlesSuggestedSeparatorComponent.
#
# Cover-art-style separator tile rendered between the LEFT half
# ("bundles this game is in") and the RIGHT half ("suggested
# bundles") of the /games/:id bundles section. Replaces the old
# `.bundles-section-divider` vertical hairline.
#
# Two-column inner layout (2026-05-19 restructure):
#   - LEFT column: stacked label rows ("suggested" / "bundles") in
#     `.bundles-suggested-separator__label` (display: flex column).
#   - RIGHT column: vertical stack of `>` glyphs in
#     `.bundles-suggested-separator__chevrons`, stacked flush
#     (zero gap, `line-height: 1`) and hugging the tile's right
#     edge, cueing the transition into the suggested half.
#
# Soft-count pattern (2026-05-19 refinement): the component renders
# 12 chevrons as a comfortable rendered count. The visible result
# is governed by the chevrons column's CSS architecture —
# `justify-content: center` + `overflow: hidden` on the column +
# `justify-content: space-between` on the parent tile — which makes
# the column hug the inner right border without negative margins
# and clips any surplus glyphs symmetrically top + bottom. The
# rendered count is therefore a SOFT contract (the spec still
# asserts 12 at the DOM layer so any future change to the constant
# stays intentional, but the CSS no longer pins the count as a
# fit-ceiling the way the prior magic-margin layout did).
#
# Asserted contract:
#   - Outer element carries the `.bundles-suggested-separator` class
#     (load-bearing for the CSS `:has(.bundles-suggested-separator:first-child)`
#     no-left-gap edge-case rule consumed by
#     `.game-bundles .shelf-row`).
#   - Inner `.bundles-suggested-separator__label` contains two
#     `.bundles-suggested-separator__label-row` rows with the
#     "suggested" / "bundles" copy.
#   - Inner `.bundles-suggested-separator__chevrons` contains
#     `CHEVRONS.size` (12) `.bundles-suggested-separator__chevron`
#     children, each a single `>` glyph. The center-justified +
#     overflow-clipped column on `.bundles-suggested-separator__chevrons`
#     handles any surplus or shortfall symmetrically without
#     load-bearing pixel-offset corrections, so the count is a soft
#     contract — bumpable in either direction without breaking the
#     layout.
#   - `aria-hidden="true"` — the separator is decorative; the row
#     itself already announces "bundles" via the section's
#     aria-label and the suggested tiles each carry their own
#     aria-labels.
RSpec.describe Games::BundlesSuggestedSeparatorComponent, type: :component do
  it "renders the outer .bundles-suggested-separator container with aria-hidden" do
    render_inline(described_class.new)

    expect(page).to have_css("div.bundles-suggested-separator[aria-hidden='true']", count: 1)
  end

  it "renders the stacked label rows ('suggested' / 'bundles') inside the label column" do
    render_inline(described_class.new)

    expect(page).to have_css(
      "div.bundles-suggested-separator span.bundles-suggested-separator__label"
    )
    expect(page).to have_css(
      "span.bundles-suggested-separator__label span.bundles-suggested-separator__label-row",
      text: "suggested"
    )
    expect(page).to have_css(
      "span.bundles-suggested-separator__label span.bundles-suggested-separator__label-row",
      text: "bundles"
    )
    expect(page).to have_css(
      "span.bundles-suggested-separator__label span.bundles-suggested-separator__label-row",
      count: 2
    )
  end

  it "renders the chevrons column wrapper inside the separator tile" do
    render_inline(described_class.new)

    expect(page).to have_css(
      "div.bundles-suggested-separator > span.bundles-suggested-separator__chevrons",
      count: 1
    )
  end

  it "renders the chevron stack (CHEVRONS.size single-glyph rows) — the CSS center-justify + overflow clip handles surplus" do
    render_inline(described_class.new)

    expected_count = described_class::CHEVRONS.size
    expect(expected_count).to eq(12) # contract guard — bump together with the constant.

    expect(page).to have_css(
      "span.bundles-suggested-separator__chevrons span.bundles-suggested-separator__chevron",
      count: expected_count
    )

    glyphs = page.all(
      "span.bundles-suggested-separator__chevrons span.bundles-suggested-separator__chevron"
    ).map { |n| n.text.strip }
    expect(glyphs).to eq([ ">" ] * expected_count)
  end

  it "exposes the label rows and chevrons via the public readers (mirrors the constants)" do
    instance = described_class.new
    expected_chevrons = [ ">" ] * 12

    expect(instance.label_row_1).to eq("suggested")
    expect(instance.label_row_2).to eq("bundles")
    expect(instance.chevrons).to eq(expected_chevrons)
    expect(instance.chevrons).to be_frozen

    expect(described_class::LABEL_ROW_1).to eq("suggested")
    expect(described_class::LABEL_ROW_2).to eq("bundles")
    expect(described_class::CHEVRONS).to eq(expected_chevrons)
    expect(described_class::CHEVRONS.size).to eq(12)
    expect(described_class::CHEVRONS).to be_frozen
  end

  it "renders exactly one root element so the tile is a single flex child of the shelf row" do
    # The CSS `.game-bundles .shelf-row:has(.bundles-suggested-separator:first-child)`
    # rule assumes the component contributes ONE child to `.shelf-row`.
    # Multiple top-level nodes would break the `:first-child` match
    # when the separator is supposed to be flush with the pane edge.
    rendered = render_inline(described_class.new)
    top_level_elements = rendered.children.reject { |n| n.text? && n.text.strip.empty? }

    expect(top_level_elements.size).to eq(1)
    expect(top_level_elements.first.name).to eq("div")
    expect(top_level_elements.first["class"]).to include("bundles-suggested-separator")
  end
end
