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
