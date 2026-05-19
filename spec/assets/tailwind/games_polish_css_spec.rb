require "rails_helper"

# 2026-05-11 polish (Fix 1 + Fix 2 + Fix 4) — `app/assets/tailwind/application.css`.
#
# Locks the canonical CSS variables and selectors introduced by the
# 2026-05-11 games polish wave:
#
#   * `--color-rating-*`     six-tier rating palette (Fix 2)
#   * `--col-width-*`        canonical column widths (Fix 1)
#   * outer-genres hairline  migrated from `_genres_shelf.html.erb` (Fix 4)
#
# (The `.games-list-mode` list/grid display-mode rules were retired
# alongside task #166 — 22 CSS rules deleted when /games dropped its
# list-mode toggle.)
#
# A blunt source-string check is enough — these are intentional
# tokens; a future rename should update both the spec and the
# stylesheet together.
RSpec.describe "application.css — 2026-05-11 games polish", type: :asset do
  let(:css_path) { Rails.root.join("app/assets/tailwind/application.css") }
  let(:css) { File.read(css_path) }

  describe "Fix 2 — six-tier rating palette" do
    %w[
      --color-rating-excellent
      --color-rating-good
      --color-rating-fair
      --color-rating-meh
      --color-rating-poor
      --color-rating-bad
    ].each do |token|
      it "declares `#{token}` for light mode" do
        # Token appears at least once in the light-mode scope (`:root`)
        # and once in the dark-mode scope (`[data-theme="dark"]`).
        expect(css.scan(/^\s*#{Regexp.escape(token)}:/m).length).to be >= 2
      end
    end
  end

  describe "Fix 1 — canonical column widths" do
    %w[
      --col-width-select
      --col-width-cover
      --col-width-genre
      --col-width-released
      --col-width-rating
      --col-width-owned
    ].each do |token|
      it "declares `#{token}`" do
        expect(css).to include(token)
      end
    end

    it "pins `--col-width-select` to 36px (canonical app-wide select column)" do
      expect(css).to match(/--col-width-select:\s*36px/)
    end

    it "pins `--col-width-cover` to 68px (matches the shelf-variant cover width)" do
      expect(css).to match(/--col-width-cover:\s*68px/)
    end
  end

  describe "Fix 4 — migrated inline styles" do
    it "carries the outer-genres sub-shelf hairline rule" do
      expect(css).to include('section[data-shelf="outer-genres"] > section.sub-shelf:not(:first-of-type)')
      expect(css).to match(/border-top:\s*1px solid var\(--color-border\)/)
    end
  end
end
