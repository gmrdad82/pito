require "rails_helper"

# 2026-05-18 (live cover refresh) — wrapper partial for the bundles
# modal composite cover. The partial is the Turbo Stream replace
# target `BundleCoverBuild` broadcasts into after a membership
# change rebuilds the composite. It MUST:
#
#   1. Render a `<div id="bundle_modal_composite_<id>">` wrapper
#      regardless of populated / empty bundle state — the broadcast
#      target id is stable across membership-state transitions
#      (empty → populated on first add, populated → empty on last
#      remove).
#   2. Branch its inner content between `Bundles::ModalCompositeComponent`
#      (populated) and `Bundles::EmptyCoverPlaceholderComponent`
#      (empty).
RSpec.describe "bundles/_modal_composite.html.erb", type: :view do
  describe "populated bundle" do
    let(:bundle) do
      b = build_stubbed(:bundle, id: 42, name: "Souls Likes")
      games = build_stubbed_list(:game, 3, cover_image_id: "abc123")
      allow(b).to receive(:games).and_return(games)
      b
    end

    before { render partial: "bundles/modal_composite", locals: { bundle: bundle } }

    it "wraps the composite in id='bundle_modal_composite_<id>'" do
      expect(rendered).to include('id="bundle_modal_composite_42"')
    end

    it "renders the populated CSS-composite (.bundle-modal-composite)" do
      expect(rendered).to include("bundle-modal-composite")
    end

    it "does NOT render the empty placeholder" do
      expect(rendered).not_to include("bundle-tile__nocover-netflix3")
    end
  end

  describe "empty bundle" do
    let(:bundle) do
      b = build_stubbed(:bundle, id: 9, name: "Pending")
      allow(b).to receive(:games).and_return([])
      b
    end

    before { render partial: "bundles/modal_composite", locals: { bundle: bundle } }

    it "still wraps the empty state in id='bundle_modal_composite_<id>' (stable Turbo Stream target)" do
      expect(rendered).to include('id="bundle_modal_composite_9"')
    end

    it "renders the netflix-3 placeholder with the --modal modifier" do
      expect(rendered).to include("bundle-tile__nocover-netflix3--modal")
    end

    it "does NOT render the populated CSS-composite cells" do
      expect(rendered).not_to include("bundle-modal-cell")
    end
  end
end
