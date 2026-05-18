require "rails_helper"

# 2026-05-18 — generic chrome partial for an omnisearch results
# section. Used by `/games`-area combined results and `/bundles`
# add-modal results; future surfaces (`/projects`, `/videos`,
# `/channels`) reuse it. The partial owns the heading + leading
# hairline + empty-state copy + `<ul>`/`<li>` wrappers. Per-row
# markup belongs to the caller and is supplied via a block.
RSpec.describe "shared/_search_section.html.erb", type: :view do
  def render_section(items:, heading: "GAMES", empty_copy: "no results.", first: false, &block)
    # ActionView treats `render(partial: …)` with a block as a
    # *collection* render when the locals hash carries `partial:` — and
    # then it asks each item for `to_partial_path` (hence the misleading
    # "nil is not ActiveModel-compatible" error when items is empty / not
    # a model collection). The positional form
    # `render("shared/search_section", locals_hash) do |item| … end`
    # bypasses that branch and yields the block per item correctly.
    output = view.render("shared/search_section",
                         heading: heading, items: items, empty_copy: empty_copy, first: first, &block)
    @rendered = output
    output
  end

  describe "happy: items present, non-first section" do
    before do
      render_section(items: %w[alpha bravo charlie], heading: "GAMES", first: false) do |item|
        view.tag.span(item, class: "row-#{item}")
      end
    end

    it "renders the heading text" do
      expect(rendered).to include("GAMES")
    end

    it "wraps the heading in the section-heading class" do
      expect(rendered).to match(%r{<h3[^>]*class="omnisearch-section-heading"[^>]*>\s*GAMES\s*</h3>})
    end

    it "renders a leading hairline because first is false" do
      expect(rendered).to include('<hr class="hairline"')
    end

    it "wraps rows in the omnisearch-section + omnisearch-list classes" do
      expect(rendered).to include('class="omnisearch-section"')
      expect(rendered).to include('class="omnisearch-list"')
    end

    it "yields each item to the block in order" do
      first_index   = rendered.index("row-alpha")
      second_index  = rendered.index("row-bravo")
      third_index   = rendered.index("row-charlie")

      expect(first_index).to be < second_index
      expect(second_index).to be < third_index
    end

    it "wraps each yielded row inside an <li class=\"omnisearch-row\">" do
      expect(rendered.scan(%r{<li class="omnisearch-row">}).length).to eq(3)
    end

    it "does NOT render the empty-state copy" do
      expect(rendered).not_to include("no results.")
    end
  end

  describe "first: true suppresses the leading hairline" do
    it "renders no <hr> when first: true and items present" do
      render_section(items: [ "only" ], first: true) do |item|
        view.tag.span(item)
      end
      expect(rendered).not_to include('<hr class="hairline"')
    end

    it "renders no <hr> when first: true and items empty" do
      render_section(items: [], first: true, empty_copy: "nothing here.")
      expect(rendered).not_to include('<hr class="hairline"')
    end

    it "still renders the heading when first: true and items empty" do
      render_section(items: [], first: true, heading: "ON IGDB", empty_copy: "nothing.")
      expect(rendered).to include("ON IGDB")
    end
  end

  describe "edge: items.empty? renders the empty-state copy" do
    before do
      render_section(
        items: [],
        heading: "ON IGDB",
        empty_copy: "no igdb results for 'doom'.",
        first: false
      )
    end

    it "renders the empty copy inside a text-muted paragraph" do
      # ERB auto-escapes the apostrophe — `&#39;` in the rendered HTML.
      expect(rendered).to match(%r{<p class="text-muted">\s*no igdb results for &#39;doom&#39;\.\s*</p>})
    end

    it "still renders the heading above the empty copy" do
      expect(rendered).to include("ON IGDB")
      heading_idx = rendered.index("ON IGDB")
      # Apostrophe is escaped as `&#39;` in the rendered HTML.
      empty_idx   = rendered.index("no igdb results for &#39;doom&#39;.")
      expect(heading_idx).to be < empty_idx
    end

    it "does NOT render the <ul> wrapper when items are empty" do
      expect(rendered).not_to include('class="omnisearch-list"')
    end

    it "still renders the leading hairline because first is false" do
      expect(rendered).to include('<hr class="hairline"')
    end
  end

  describe "block yields the exact item object the caller passed in" do
    it "passes each item through to the block argument unchanged" do
      seen = []
      render_section(items: [ { id: 1, label: "one" }, { id: 2, label: "two" } ]) do |item|
        seen << item
        view.tag.span(item[:label])
      end

      expect(seen).to eq([ { id: 1, label: "one" }, { id: 2, label: "two" } ])
      expect(rendered).to include("one")
      expect(rendered).to include("two")
    end
  end

  describe "edge: empty + first combination — minimal chrome, no hairline" do
    # Sanity coverage for the "no preceding context" case the spec
    # checklist calls out: when there's nothing prior in the modal
    # AND this section has no items, the partial renders the heading
    # + empty copy ONLY — no hairline, no `<ul>`.
    before { render_section(items: [], first: true, heading: "GAMES", empty_copy: "nothing.") }

    it "renders no hairline" do
      expect(rendered).not_to include('<hr class="hairline"')
    end

    it "renders no <ul>" do
      expect(rendered).not_to include('class="omnisearch-list"')
    end

    it "renders the heading" do
      expect(rendered).to include("GAMES")
    end

    it "renders the empty copy" do
      expect(rendered).to include("nothing.")
    end
  end
end
