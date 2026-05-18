require "rails_helper"

# 2026-05-18 — `DELETE /bundles/:id` after the on-page confirm-modal +
# Turbo Stream destroy flow lands. The legacy `/deletions/bundle/:ids`
# action-confirmation route was retired; the per-bundle delete is now
# triggered by `ConfirmModalComponent` (rendered as a sibling of each
# bundle tile in `_bundles_for_shelf`) and the controller responds
# with:
#
#   - turbo_stream branch — removes `#bundle-tile-<id>`, replaces
#     `#bundles-modal` with the steady-state render, removes the
#     per-bundle `#confirm_delete_bundle_<id>` dialog, and appends a
#     flash toast.
#   - HTML branch          — redirects to `/games` with the same flash
#     notice (JS-off / direct-hit fallback).
#
# The flow is reachable from both `/games` (the bundles shelf modal)
# and `/games/:id` (the per-game bundles modal); the controller
# action itself is unaware of the originating page, so the request
# specs cover the protocol-level contract that is identical for both.
RSpec.describe "DELETE /bundles/:id", type: :request do
  let!(:bundle) { create(:bundle, name: "Soulslikes") }

  describe "Turbo Stream branch" do
    let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

    it "destroys the bundle record" do
      expect {
        delete bundle_path(bundle), headers: turbo_headers
      }.to change(Bundle, :count).by(-1)
    end

    it "responds 200 with the turbo-stream media type" do
      delete bundle_path(bundle), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to include("turbo-stream")
    end

    it "emits a `remove` stream targeting the bundle's shelf tile" do
      delete bundle_path(bundle), headers: turbo_headers

      expect(response.body).to include(
        %(<turbo-stream action="remove" target="bundle-tile-#{bundle.id}">)
      )
    end

    it "emits a `replace` stream targeting #bundles-modal" do
      delete bundle_path(bundle), headers: turbo_headers

      expect(response.body).to include(
        %(<turbo-stream action="replace" target="bundles-modal">)
      )
    end

    it "the replaced #bundles-modal is the steady-state render (no `bundle:` local)" do
      delete bundle_path(bundle), headers: turbo_headers

      # Steady-state render carries an empty inline-edit URL and an
      # absent autoopen Stimulus class. Both come from the partial's
      # `local_assigns[:bundle]` fallback path.
      expect(response.body).to include('id="bundles-modal"')
      expect(response.body).not_to include("bundles-modal-autoopen")
      # Steady-state pre-fills the inline-edit URL with the empty
      # string (vs `/bundles/<id>` when a bundle is bound).
      expect(response.body).to include('data-inline-title-edit-url-value=""')
    end

    it "emits a `remove` stream targeting the per-bundle confirm dialog" do
      delete bundle_path(bundle), headers: turbo_headers

      expect(response.body).to include(
        %(<turbo-stream action="remove" target="confirm_delete_bundle_#{bundle.id}">)
      )
    end

    it "appends a flash toast with the `bundle deleted.` notice" do
      delete bundle_path(bundle), headers: turbo_headers

      expect(response.body).to include('<turbo-stream action="append" targets=".toast-container">')
      expect(response.body).to include("bundle deleted.")
    end
  end

  describe "HTML fallback (JS-off / direct hit)" do
    it "destroys the bundle record" do
      expect {
        delete bundle_path(bundle)
      }.to change(Bundle, :count).by(-1)
    end

    it "redirects to /games" do
      delete bundle_path(bundle)

      expect(response).to redirect_to(games_path)
    end

    it "carries the `bundle deleted.` flash notice through the redirect" do
      delete bundle_path(bundle)

      expect(flash[:notice]).to eq("bundle deleted.")
    end
  end

  describe "404 path" do
    it "returns 404 when the bundle does not exist" do
      delete "/bundles/999999"
      expect(response).to have_http_status(:not_found)
    end
  end
end
