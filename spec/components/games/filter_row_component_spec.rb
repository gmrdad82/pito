require "rails_helper"

# Phase 27 v2 spec 06 — Filter row (single compact band).
RSpec.describe Games::FilterRowComponent, type: :component do
  let(:universe) { Games::FiltersHelper::TOKEN_UNIVERSE }

  describe "happy: default rendering (no checked_tokens passed)" do
    before { render_inline(described_class.new) }

    it "defaults to every chip CHECKED (the full-list state)" do
      # All 8 chips render with the `chip--active` modifier (GoG +
      # Epic were collapsed into Steam in the 2026-05-17 PC store
      # collapse).
      expect(page).to have_css("a.filter-chip.chip--active", count: 8)
    end

    it "renders 8 chips total (5 left + 3 right)" do
      expect(page).to have_css("a.filter-chip", count: 8)
    end

    it "renders left side chips in the locked order (status + ownership)" do
      left_tokens = page.all(".games-filter-row__left a.filter-chip")
                        .map { |a| a["data-filter-token"] }
      expect(left_tokens).to eq(%w[released scheduled owned wishlist played])
    end

    it "renders right side chips in the locked order (PS5, Switch2, Steam — no xbox, no gog, no epic)" do
      right_tokens = page.all(".games-filter-row__right a.filter-chip")
                         .map { |a| a["data-filter-token"] }
      expect(right_tokens).to eq(%w[ps5 switch2 steam])
    end

    it "does NOT render an xbox chip" do
      expect(page).to have_no_css("a[data-filter-token='xbox']")
    end

    it "does NOT render a gog chip (collapsed into steam 2026-05-17)" do
      expect(page).to have_no_css("a[data-filter-token='gog']")
    end

    it "does NOT render an epic chip (collapsed into steam 2026-05-17)" do
      expect(page).to have_no_css("a[data-filter-token='epic']")
    end

    it "does NOT render the legacy `[clear all]` link" do
      expect(page).to have_no_link("clear all")
    end

    it "does NOT render the legacy contradiction notice" do
      expect(page).to have_no_css(".games-filter-row__contradiction")
    end

    it "does NOT render the recorded chip (retired in v2)" do
      expect(page).to have_no_css("a[data-filter-token='recorded']")
    end

    it "does NOT render the not_owned chip (retired in v2 — wishlist replaces)" do
      expect(page).to have_no_css("a[data-filter-token='not_owned']")
    end

    it "mounts the games-filter Stimulus controller on the outer wrapper" do
      expect(page).to have_css("section.games-filter-row[data-controller='games-filter']")
    end

    it "stamps the universe value so the controller knows when to collapse the URL" do
      universe_value = page.find("section.games-filter-row")["data-games-filter-universe-value"]
      expect(JSON.parse(universe_value)).to eq(universe)
    end

    it "stamps the frame id so the controller knows which Turbo Frame to refresh" do
      frame_id = page.find("section.games-filter-row")["data-games-filter-frame-id-value"]
      expect(frame_id).to eq("games_listing")
    end
  end

  describe "happy: partial-checked set rendering" do
    before do
      render_inline(described_class.new(checked_tokens: %w[ps5 owned released]))
    end

    it "renders only the 3 specified chips as checked" do
      expect(page).to have_css("a.filter-chip.chip--active", count: 3)
    end

    it "marks released, owned, and ps5 as checked" do
      %w[released owned ps5].each do |t|
        expect(page).to have_css("a.filter-chip.chip--active[data-filter-token='#{t}']")
      end
    end

    it "marks scheduled, wishlist, played, switch2, steam as unchecked" do
      %w[scheduled wishlist played switch2 steam].each do |t|
        expect(page).to have_css("a.filter-chip[data-filter-token='#{t}']")
        expect(page).to have_no_css("a.filter-chip.chip--active[data-filter-token='#{t}']")
      end
    end
  end

  describe "happy: empty checked-token set" do
    before { render_inline(described_class.new(checked_tokens: [])) }

    it "renders every chip as unchecked" do
      expect(page).to have_no_css("a.filter-chip.chip--active")
      expect(page).to have_css("a.filter-chip", count: 8)
    end
  end

  describe "PLATFORM_LABELS short-label rendering" do
    before { render_inline(described_class.new) }

    {
      "ps5"     => "PS5",
      "switch2" => "Switch2",
      "steam"   => "Steam"
    }.each do |token, label|
      it "renders the #{token} chip with short label #{label.inspect}" do
        chip = page.find("a[data-filter-token='#{token}']")
        expect(chip.text).to include(label)
      end
    end
  end

  describe "flaw: defensive surface" do
    before { render_inline(described_class.new(checked_tokens: %w[ps5])) }

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits a <script> tag" do
      expect(page.native.to_html).not_to include("<script")
    end

    it "never invokes window.confirm / alert / prompt" do
      html = page.native.to_html
      expect(html).not_to include("window.confirm")
      expect(html).not_to include("alert(")
      expect(html).not_to include("prompt(")
    end

    it "never emits text-danger on chips (red is reserved for destructive)" do
      expect(page).to have_no_css(".filter-chip.text-danger")
    end
  end
end
