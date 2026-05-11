require "rails_helper"

# Phase 27 §01b — Filter row component.
RSpec.describe Games::FilterRowComponent, type: :component do
  let(:request_path) { "/games" }

  describe "happy: rendering" do
    before do
      render_inline(described_class.new(
        active_tokens: [], request_path: request_path
      ))
    end

    it "renders all ten canonical chips" do
      expect(page).to have_css("a.filter-chip", count: 10)
    end

    it "renders chips in the locked left-to-right order" do
      tokens = page.all("a.filter-chip").map { |a| a["data-filter-token"] }
      expect(tokens).to eq(%w[recorded released owned not_owned scheduled ps5 switch2 steam gog epic])
    end

    it "does NOT render [clear all] when no chip is active" do
      expect(page).to have_no_css(".games-filter-row__clear-all")
    end

    it "does NOT render the contradiction notice by default" do
      expect(page).to have_no_css(".games-filter-row__contradiction")
    end
  end

  describe "happy: with active chips" do
    before do
      render_inline(described_class.new(
        active_tokens: [ "ps5" ], request_path: request_path
      ))
    end

    it "renders [clear all] when at least one chip is active" do
      expect(page).to have_css(".games-filter-row__clear-all", text: "clear all")
    end

    it "[clear all] href clears filters= from the URL" do
      href = page.find(".games-filter-row__clear-all-link")["href"]
      expect(href).to eq("/games")
      expect(href).not_to include("filters=")
    end

    it "applies chip--active on the active chip only" do
      expect(page).to have_css("a.filter-chip.chip--active[data-filter-token='ps5']")
      # No other chip is active.
      expect(page.all("a.filter-chip.chip--active").size).to eq(1)
    end
  end

  describe "happy: contradiction notice" do
    before do
      render_inline(described_class.new(
        active_tokens: %w[owned not_owned], request_path: request_path,
        contradiction: true
      ))
    end

    it "renders the contradiction notice" do
      expect(page).to have_css(".games-filter-row__contradiction",
                               text: "(owned and not owned together — no matches)")
    end

    it "uses text-muted class (not danger)" do
      expect(page).to have_css(".games-filter-row__contradiction.text-muted")
    end

    it "renders no red / danger styling" do
      expect(page.native.to_html).not_to include("text-danger")
    end
  end

  describe "edge: query_string_overrides preservation" do
    it "preserves display=list on [clear all] href" do
      render_inline(described_class.new(
        active_tokens: %w[ps5], request_path: request_path,
        query_string_overrides: { display: "list" }
      ))
      href = page.find(".games-filter-row__clear-all-link")["href"]
      expect(href).to eq("/games?display=list")
    end

    it "preserves display=list on every chip href" do
      render_inline(described_class.new(
        active_tokens: [], request_path: request_path,
        query_string_overrides: { display: "list" }
      ))
      page.all("a.filter-chip").each do |a|
        expect(a["href"]).to include("display=list")
      end
    end

    it "preserves genre=action on chip hrefs" do
      render_inline(described_class.new(
        active_tokens: [], request_path: request_path,
        query_string_overrides: { genre: "action" }
      ))
      ps5_href = page.find("a[data-filter-token='ps5']")["href"]
      expect(ps5_href).to include("genre=action")
    end
  end

  describe "sad: invalid inputs" do
    it "does NOT render the contradiction notice when contradiction is false" do
      render_inline(described_class.new(
        active_tokens: %w[ps5], request_path: request_path, contradiction: false
      ))
      expect(page).to have_no_css(".games-filter-row__contradiction")
    end
  end

  describe "polish: [ clear all ] inner spaces (2026-05-11)" do
    # Per the bracketed-link convention, MULTI-word labels carry inner
    # spaces: `[ clear all ]`. Single-token chip labels above stay
    # flush against the brackets (`[ps5]`). See
    # `feedback_bracketed_links.md`.
    it "renders [ clear all ] with inner spaces around the multi-word label" do
      render_inline(described_class.new(
        active_tokens: %w[ps5], request_path: request_path
      ))
      html = page.native.to_html
      # `[<SPACE><span>clear all</span><SPACE>]` — the canonical
      # multi-word shape from the convention.
      expect(html).to match(%r{\[ <span class="bl">clear all</span> \]})
    end

    it "still resolves [clear all]'s text content to the bare label" do
      render_inline(described_class.new(
        active_tokens: %w[ps5], request_path: request_path
      ))
      expect(page).to have_link("clear all")
    end
  end

  describe "polish: right_slot (2026-05-11)" do
    # The display-mode switcher (Phase 27 §01d) used to sit flush-right
    # of `<h1>games</h1>`. It now lands in the filter row's optional
    # right slot via `with_right_slot`. Slot content renders inside
    # `.games-filter-row__right`, which uses `margin-left: auto` to pin
    # the slot flush-right regardless of how many chips wrap.
    it "renders the right_slot inside `.games-filter-row__right` when provided" do
      render_inline(described_class.new(
        active_tokens: [], request_path: request_path
      )) do |row|
        row.with_right_slot { "<span class=\"switcher-stub\">SWITCHER</span>".html_safe }
      end

      expect(page).to have_css(".games-filter-row__right .switcher-stub", text: "SWITCHER")
    end

    it "pins the right slot flush-right via `margin-left: auto`" do
      render_inline(described_class.new(
        active_tokens: [], request_path: request_path
      )) do |row|
        row.with_right_slot { "<span class=\"switcher-stub\">SWITCHER</span>".html_safe }
      end

      style = page.find(".games-filter-row__right")["style"]
      expect(style).to include("margin-left: auto")
    end

    it "does NOT render `.games-filter-row__right` when no slot is provided" do
      render_inline(described_class.new(
        active_tokens: [], request_path: request_path
      ))
      expect(page).to have_no_css(".games-filter-row__right")
    end

    it "places the right slot AFTER the chips in document order" do
      render_inline(described_class.new(
        active_tokens: [], request_path: request_path
      )) do |row|
        row.with_right_slot { "<span class=\"switcher-stub\">SWITCHER</span>".html_safe }
      end

      html = page.native.to_html
      chips_idx = html.index('class="games-filter-row__chips"')
      right_idx = html.index('class="games-filter-row__right"')
      expect(chips_idx).to be < right_idx
    end
  end

  describe "flaw: defensive surface" do
    before do
      render_inline(described_class.new(
        active_tokens: %w[ps5 owned], request_path: request_path
      ))
    end

    it "never emits data-turbo-confirm anywhere" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits a <script> tag" do
      expect(page.native.to_html).not_to include("<script")
    end

    it "never invokes window.confirm / alert / prompt in rendered HTML" do
      html = page.native.to_html
      expect(html).not_to include("window.confirm")
      expect(html).not_to include("alert(")
      expect(html).not_to include("prompt(")
    end

    it "never emits text-danger on chips (red is reserved)" do
      expect(page).to have_no_css(".filter-chip.text-danger")
    end
  end
end
