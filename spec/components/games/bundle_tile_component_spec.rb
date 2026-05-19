require "rails_helper"

# Phase 27 Wave F — Games::BundleTileComponent.
#
# Bundle tile rendered in two surfaces:
#
#   * `/games` Bundles outer shelf row (150 × 200, default mode) — the
#     anchor opens the layout-level bundles modal via the
#     `bundles-modal-trigger` Stimulus controller.
#   * `/games/:id` bundles section (98 × 130, suggest mode) — wraps the
#     cover in a `button_to` POST `/bundles/:slug/members` so clicking
#     adds the supplied `target_game:` to the bundle.
#
# Each tile shows either the bundle's composite cover (when
# `BundleCoverBuild` has produced one) or the netflix-3 placeholder
# (three-cell grid mirroring `Composite::CellMap.for(3)`, with a
# light/dark controller-icon SVG pair stacked in each cell). The
# `+N` overflow overlay (a `StatusBadgeComponent` at `:neutral`) is
# rendered flush bottom-right when the bundle holds more than nine
# members.
RSpec.describe Games::BundleTileComponent, type: :component do
  # Helper — build a stubbed bundle and stub the membership-related
  # methods the component reads (`#bundle_members`,
  # `#composite_cover_url`). Using `build_stubbed` keeps the spec
  # database-free; the component never persists.
  def stub_bundle(name: "My Bundle", id: 42, slug: "my-bundle",
                  composite_url: nil, member_count: 0)
    bundle = build_stubbed(:bundle, id: id, name: name)
    allow(bundle).to receive(:slug).and_return(slug)
    allow(bundle).to receive(:composite_cover_url).and_return(composite_url)
    members = Array.new(member_count) { Object.new }
    allow(bundle).to receive(:bundle_members).and_return(members)
    bundle
  end

  let(:target_game) do
    build_stubbed(:game, :synced,
                  id: 1234,
                  title: "Halo Infinite",
                  igdb_slug: "halo-infinite")
  end

  # ----------------------------------------------------------------
  # Constructor validation — size + mode whitelists.
  # ----------------------------------------------------------------

  describe "constructor validation" do
    it "defaults size to :grid and mode to :default" do
      expect {
        described_class.new(bundle: stub_bundle)
      }.not_to raise_error
    end

    it "accepts size: :shelf" do
      expect {
        described_class.new(bundle: stub_bundle, size: :shelf)
      }.not_to raise_error
    end

    it "raises ArgumentError on unknown size" do
      expect {
        described_class.new(bundle: stub_bundle, size: :huge)
      }.to raise_error(ArgumentError, /Unknown bundle tile size/)
    end

    it "raises ArgumentError on unknown mode" do
      expect {
        described_class.new(bundle: stub_bundle, mode: :bogus)
      }.to raise_error(ArgumentError, /Unknown bundle tile mode/)
    end

    it "raises ArgumentError when mode: :suggest is given without target_game" do
      expect {
        described_class.new(bundle: stub_bundle, mode: :suggest)
      }.to raise_error(ArgumentError, /target_game/)
    end
  end

  # ----------------------------------------------------------------
  # Live cover refresh — dom_id wrapper + Turbo Stream subscription
  # the `BundleCoverBuild` Sidekiq job broadcasts into.
  # ----------------------------------------------------------------

  describe "live cover refresh wiring" do
    let(:bundle) do
      stub_bundle(name: "Souls Likes", id: 42, slug: "souls-likes",
                  composite_url: "/covers/bundles/42/composite.jpg",
                  member_count: 3)
    end

    it "wraps the cover in id='bundle_cover_<id>' so Turbo Stream replaces land cleanly" do
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css("#bundle_cover_42")
    end

    it "subscribes to the per-bundle 'bundle_cover:<id>' stream via turbo_stream_from" do
      render_inline(described_class.new(bundle: bundle))
      # `turbo_stream_from` renders a `<turbo-cable-stream-source>`
      # custom element. The signed-stream-name attribute is encrypted,
      # so assert structure (element presence) rather than the name.
      expect(page.native.to_html).to include("turbo-cable-stream-source")
    end

    it "appends ?v=<bundle.updated_at.to_i> to the composite img src as cache buster" do
      ts = Time.utc(2026, 5, 18, 12, 0, 0)
      allow(bundle).to receive(:updated_at).and_return(ts)
      render_inline(described_class.new(bundle: bundle))
      img = page.find("img.bundle-cover-composite")
      expect(img["src"]).to eq("/covers/bundles/42/composite.jpg?v=#{ts.to_i}")
    end
  end

  # ----------------------------------------------------------------
  # Default mode — anchor wrapper + bundles-modal-trigger wiring.
  # ----------------------------------------------------------------

  describe "default mode — anchor wrapper" do
    let(:bundle) do
      stub_bundle(name: "Souls Likes", id: 7, slug: "souls-likes",
                  composite_url: "/covers/bundles/7/composite.jpg",
                  member_count: 3)
    end

    before { render_inline(described_class.new(bundle: bundle)) }

    it "renders an <a class='bundle-tile'> wrapper" do
      expect(page).to have_css("a.bundle-tile")
    end

    it "uses dom id 'bundle-tile-<id>' for Turbo Stream targeting" do
      expect(page).to have_css("a#bundle-tile-7")
    end

    it "sets data-bundle-id to the bundle id" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["data-bundle-id"]).to eq("7")
    end

    it "wires the bundles-modal-trigger Stimulus controller" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["data-controller"]).to eq("bundles-modal-trigger")
      expect(anchor["data-action"]).to eq("click->bundles-modal-trigger#open")
    end

    it "sets data-bundles-modal-trigger-url-value to /bundles/:slug/games_pane" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["data-bundles-modal-trigger-url-value"]).to eq("/bundles/souls-likes/games_pane")
    end

    it "sets data-bundles-modal-trigger-title-value to the bundle name" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["data-bundles-modal-trigger-title-value"]).to eq("Souls Likes")
    end

    it "sets data-bundles-modal-trigger-update-url-value to /bundles/:slug" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["data-bundles-modal-trigger-update-url-value"]).to eq("/bundles/souls-likes")
    end

    it "sets data-bundles-modal-trigger-delete-confirm-id-value to the per-bundle dialog id" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["data-bundles-modal-trigger-delete-confirm-id-value"]).to eq("confirm_delete_bundle_7")
    end

    it "uses /bundles/:slug as the href fallback for JS-off clients" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["href"]).to eq("/bundles/souls-likes")
    end

    it "sets title= and (for default mode) NOT an add-aria label" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["title"]).to eq("Souls Likes")
      # default mode uses the bare bundle name; no "add to …" copy
      expect(anchor["title"]).not_to match(/add to/i)
    end

    it "pins the wrapper to 150px (grid size)" do
      anchor = page.find("a.bundle-tile")
      expect(anchor["style"]).to include("width: 150px")
    end
  end

  # ----------------------------------------------------------------
  # Composite cover render path.
  # ----------------------------------------------------------------

  describe "composite cover render" do
    let(:bundle) do
      stub_bundle(composite_url: "/covers/bundles/7/composite.jpg",
                  member_count: 5)
    end

    before { render_inline(described_class.new(bundle: bundle)) }

    it "renders the composite <img> with the bundle name as alt" do
      img = page.find("img.bundle-cover-composite")
      # The src is decorated with a `?v=<bundle.updated_at.to_i>`
      # cache buster (see "live cover refresh wiring" group); assert
      # the path prefix here so the existing happy-path test stays
      # focused on the cover render path itself.
      expect(img["src"]).to start_with("/covers/bundles/7/composite.jpg?v=")
      expect(img["alt"]).to eq(bundle.name)
    end

    it "uses the grid 150x200 dimensions" do
      img = page.find("img.bundle-cover-composite")
      expect(img["width"]).to eq("150")
      expect(img["height"]).to eq("200")
    end

    it "lazy-loads the composite cover" do
      img = page.find("img.bundle-cover-composite")
      expect(img["loading"]).to eq("lazy")
    end

    it "does NOT render the netflix-3 placeholder" do
      expect(page).to have_no_css(".bundle-tile__nocover-netflix3")
    end
  end

  # ----------------------------------------------------------------
  # Empty bundle (no composite) — netflix-3 placeholder.
  # ----------------------------------------------------------------

  describe "empty bundle placeholder (netflix-3)" do
    let(:bundle) { stub_bundle(name: "Empty", composite_url: nil, member_count: 0) }

    before { render_inline(described_class.new(bundle: bundle)) }

    it "renders the .bundle-tile__nocover-netflix3 container" do
      expect(page).to have_css(".bundle-tile__nocover-netflix3")
    end

    it "renders three cells (one .cell--main + two .cell)" do
      expect(page).to have_css(".bundle-tile__nocover-netflix3 > .cell", count: 3)
      expect(page).to have_css(".bundle-tile__nocover-netflix3 > .cell--main", count: 1)
    end

    it "embeds three controller-icon imgs (single-dark, one per cell)" do
      # 2026-05-19 — theme system removed; the dual light/dark image
      # pair collapsed to a single _dark.svg image per cell.
      expect(page).to have_css(".bundle-tile__nocover-netflix3 img", count: 3)
      expect(page).to have_no_css(".bundle-tile__nocover-netflix3 img[data-theme='light']")
      expect(page).to have_no_css(".bundle-tile__nocover-netflix3 img[data-theme='dark']")
    end

    it "uses the --large size in the main cell and --small in the other two" do
      expect(page).to have_css(".cell--main img.bundle-tile__nocover-icon--large", count: 1)
      expect(page).to have_css(".bundle-tile__nocover-netflix3 img.bundle-tile__nocover-icon--small", count: 2)
    end

    it "tags the container with aria-label + title set to the bundle name" do
      el = page.find(".bundle-tile__nocover-netflix3")
      expect(el["aria-label"]).to eq("Empty")
      expect(el["title"]).to eq("Empty")
    end

    it "does NOT render the composite cover <img>" do
      expect(page).to have_no_css("img.bundle-cover-composite")
    end
  end

  # ----------------------------------------------------------------
  # +N overflow overlay — strict accounting (member_count − 9).
  # ----------------------------------------------------------------

  describe "+N overflow overlay" do
    it "does NOT render the overlay at exactly 9 members" do
      bundle = stub_bundle(composite_url: "/covers/bundles/x.jpg", member_count: 9)
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_no_css(".bundle-cover-overflow-overlay")
    end

    it "renders +1 for 10 members" do
      bundle = stub_bundle(composite_url: "/covers/bundles/x.jpg", member_count: 10)
      render_inline(described_class.new(bundle: bundle))
      overlay = page.find(".bundle-cover-overflow-overlay")
      expect(overlay).to have_text("+1")
    end

    it "renders +5 for 14 members" do
      bundle = stub_bundle(composite_url: "/covers/bundles/x.jpg", member_count: 14)
      render_inline(described_class.new(bundle: bundle))
      expect(page.find(".bundle-cover-overflow-overlay")).to have_text("+5")
    end
  end

  # ----------------------------------------------------------------
  # Caption — only in grid size; left-aligned ellipsis-truncated.
  # ----------------------------------------------------------------

  describe "caption (grid size)" do
    it "renders the bundle name inside .bundle-tile-name" do
      bundle = stub_bundle(name: "Souls Likes",
                           composite_url: "/x.jpg", member_count: 1)
      render_inline(described_class.new(bundle: bundle, size: :grid))
      expect(page).to have_css(".bundle-tile-name", text: "Souls Likes")
    end

    it "applies ellipsis CSS bound to the 150px slot width" do
      bundle = stub_bundle(composite_url: "/x.jpg", member_count: 1)
      render_inline(described_class.new(bundle: bundle, size: :grid))
      el = page.find(".bundle-tile-name")
      expect(el["style"]).to include("max-width: 150px")
      expect(el["style"]).to include("text-overflow: ellipsis")
      expect(el["style"]).to include("white-space: nowrap")
    end
  end

  describe "caption (shelf size)" do
    let(:bundle) { stub_bundle(name: "Shelf Bundle", composite_url: "/x.jpg", member_count: 1) }

    it "does NOT render the caption span on shelf-size tiles" do
      render_inline(described_class.new(bundle: bundle, size: :shelf))
      expect(page).to have_no_css(".bundle-tile-name")
    end

    it "pins the cover at 98x130 (shelf dimensions)" do
      render_inline(described_class.new(bundle: bundle, size: :shelf))
      img = page.find("img.bundle-cover-composite")
      expect(img["width"]).to eq("98")
      expect(img["height"]).to eq("130")
    end
  end

  # ----------------------------------------------------------------
  # Suggest mode — POST /bundles/:slug/members with target_game.
  # ----------------------------------------------------------------

  describe "mode: :suggest" do
    let(:bundle) do
      stub_bundle(name: "Indie Picks", id: 88, slug: "indie-picks",
                  composite_url: "/covers/bundles/88/composite.jpg",
                  member_count: 4)
    end

    before do
      render_inline(described_class.new(
        bundle: bundle,
        size: :shelf,
        mode: :suggest,
        target_game: target_game
      ))
    end

    it "wraps the cover in a <form> instead of an <a>" do
      expect(page).to have_css("form.bundle-tile.bundle-tile--suggest")
      expect(page).to have_no_css("a.bundle-tile")
    end

    it "POSTs the form to /bundles/:slug/members" do
      form = page.find("form.bundle-tile--suggest")
      expect(form["action"]).to eq("/bundles/indie-picks/members")
      expect(form["method"]).to eq("post")
    end

    it "submits the target game id as game_id" do
      input = page.find("form input[name='game_id']", visible: false)
      expect(input["value"]).to eq(target_game.id.to_s)
    end

    it "carries source=games_show so the controller redirects back to /games/:id" do
      input = page.find("form input[name='source']", visible: false)
      expect(input["value"]).to eq("games_show")
    end

    it "tags the form with data-bundle-id" do
      form = page.find("form.bundle-tile--suggest")
      expect(form["data-bundle-id"]).to eq("88")
    end

    it "uses the i18n add-aria label on the submit button (aria-label + title)" do
      btn = page.find("button.bundle-tile-suggest-button")
      expect(btn["aria-label"]).to eq("add to Indie Picks")
      expect(btn["title"]).to eq("add to Indie Picks")
    end

    it "renders the composite cover inside the suggest form" do
      img = page.find("form img.bundle-cover-composite")
      expect(img["src"]).to start_with("/covers/bundles/88/composite.jpg?v=")
    end

    it "uses the shelf 98x130 dimensions when size: :shelf is passed" do
      img = page.find("img.bundle-cover-composite")
      expect(img["width"]).to eq("98")
      expect(img["height"]).to eq("130")
    end
  end

  describe "mode: :suggest with an empty bundle" do
    let(:bundle) do
      stub_bundle(name: "Pending", id: 9, slug: "pending",
                  composite_url: nil, member_count: 0)
    end

    before do
      render_inline(described_class.new(
        bundle: bundle,
        size: :shelf,
        mode: :suggest,
        target_game: target_game
      ))
    end

    it "renders the netflix-3 placeholder inside the suggest form" do
      expect(page).to have_css("form .bundle-tile__nocover-netflix3")
    end

    it "still POSTs to /bundles/:slug/members" do
      form = page.find("form.bundle-tile--suggest")
      expect(form["action"]).to eq("/bundles/pending/members")
    end
  end

  # ----------------------------------------------------------------
  # Slug fallback — id-as-slug when the bundle has no friendly slug.
  # ----------------------------------------------------------------

  describe "slug fallback" do
    it "uses bundle.id when slug is blank" do
      bundle = stub_bundle(id: 314, slug: nil,
                           composite_url: "/x.jpg", member_count: 1)
      render_inline(described_class.new(bundle: bundle))
      anchor = page.find("a.bundle-tile")
      expect(anchor["href"]).to eq("/bundles/314")
      expect(anchor["data-bundles-modal-trigger-url-value"]).to eq("/bundles/314/games_pane")
    end
  end

  # ----------------------------------------------------------------
  # Hard rules — no JS confirm.
  # ----------------------------------------------------------------

  describe "flaw: no JS confirm" do
    it "default mode never emits data-turbo-confirm" do
      render_inline(described_class.new(bundle: stub_bundle(composite_url: "/x.jpg", member_count: 1)))
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "suggest mode never emits data-turbo-confirm" do
      render_inline(described_class.new(
        bundle: stub_bundle(composite_url: "/x.jpg", member_count: 1),
        size: :shelf,
        mode: :suggest,
        target_game: target_game
      ))
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end
  end
end
