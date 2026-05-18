require "rails_helper"

# 2026-05-18 (live cover refresh) — cover-wrap partial shared by the
# `Games::BundleTileComponent` template AND the Turbo Stream
# `replace` broadcast `BundleCoverBuild` fires after a membership
# change. The partial MUST:
#
#   1. Render a `<div id="bundle_cover_<id>">` wrapper regardless of
#      cover-present / cover-absent state — the broadcast target id
#      is stable across composite-state transitions (first build,
#      first add to empty bundle, last remove).
#   2. Decorate the composite img src with `?v=<bundle.updated_at.to_i>`
#      so the browser does not serve the stale cached cover after the
#      on-disk JPEG is rewritten.
#   3. Render the netflix-3 fallback when the composite is absent.
#   4. Surface the `+N` overflow overlay when the caller passes a
#      positive `overflow_n`.
RSpec.describe "games/_bundle_tile_cover.html.erb", type: :view do
  def stub_bundle(id:, name:, composite_url:, updated_at: Time.utc(2026, 5, 18, 12, 0, 0))
    b = build_stubbed(:bundle, id: id, name: name)
    allow(b).to receive(:composite_cover_url).and_return(composite_url)
    allow(b).to receive(:updated_at).and_return(updated_at)
    b
  end

  describe "composite-present render" do
    let(:bundle) { stub_bundle(id: 42, name: "Souls Likes", composite_url: "/covers/bundles/42/composite.jpg") }

    before do
      render partial: "games/bundle_tile_cover",
             locals: { bundle: bundle, width: 150, height: 200, overflow_n: 0 }
    end

    it "wraps the cover in id='bundle_cover_<id>'" do
      expect(rendered).to include('id="bundle_cover_42"')
    end

    it "renders the composite <img> with the cache-buster query param" do
      expect(rendered).to match(%r{src="/covers/bundles/42/composite\.jpg\?v=\d+"})
    end

    it "uses bundle.updated_at.to_i as the cache buster value" do
      expect(rendered).to include("?v=#{bundle.updated_at.to_i}")
    end

    it "does NOT render the netflix-3 placeholder" do
      expect(rendered).not_to include("bundle-tile__nocover-netflix3")
    end

    it "applies the caller's width + height to the wrapper inline style" do
      expect(rendered).to include("width: 150px")
      expect(rendered).to include("height: 200px")
    end
  end

  describe "composite-absent render" do
    let(:bundle) { stub_bundle(id: 9, name: "Pending", composite_url: nil) }

    before do
      render partial: "games/bundle_tile_cover",
             locals: { bundle: bundle, width: 98, height: 130, overflow_n: 0 }
    end

    it "still wraps the empty state in id='bundle_cover_<id>'" do
      expect(rendered).to include('id="bundle_cover_9"')
    end

    it "renders the netflix-3 placeholder" do
      expect(rendered).to include("bundle-tile__nocover-netflix3")
    end

    it "does NOT render the composite <img>" do
      expect(rendered).not_to include('class="bundle-cover-composite"')
    end
  end

  describe "+N overflow overlay" do
    let(:bundle) { stub_bundle(id: 7, name: "Big", composite_url: "/covers/bundles/7/composite.jpg") }

    it "does NOT render the overlay when overflow_n is zero" do
      render partial: "games/bundle_tile_cover",
             locals: { bundle: bundle, width: 150, height: 200, overflow_n: 0 }
      expect(rendered).not_to include("bundle-cover-overflow-overlay")
    end

    it "renders the overlay with +N when overflow_n is positive" do
      render partial: "games/bundle_tile_cover",
             locals: { bundle: bundle, width: 150, height: 200, overflow_n: 4 }
      expect(rendered).to include("bundle-cover-overflow-overlay")
      expect(rendered).to include("+4")
    end
  end
end
