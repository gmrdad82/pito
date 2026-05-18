// 2026-05-18 — Bundle add-trigger.
//
// Wires a click on a bare cover tile (omnisearch recommendations
// shelf inside the `:bundle_add` modal) to a POST against
// `/bundles/:bundle_id/members` so the game gets appended to the
// bundle without a full-page navigation. Mirrors the [+] suggest-
// tile click target on the bundle show page — both surfaces hit the
// same controller endpoint (BundleMembersController#create).
//
// Values:
//   bundleId — integer Bundle id (the URL accepts a slug too via
//              `Bundle.friendly.find`, but the modal renders with
//              the numeric id since the bundle object is already
//              loaded server-side).
//   gameId   — integer Game id (BundleMembersController also accepts
//              a slug per Phase 20 friendly URLs).
//
// On success the server responds with either an HTML redirect
// (default Rails redirect_to) or a turbo_stream payload — when the
// `Accept: text/vnd.turbo-stream.html` header negotiates a stream
// response, `Turbo.renderStreamMessage` applies it. Otherwise the
// page reloads so the bundle's member list reflects the new row.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { bundleId: Number, gameId: Number }

  async add(event) {
    event.preventDefault()
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const formData = new FormData()
    formData.append("game_id", this.gameIdValue)

    const response = await fetch(`/bundles/${this.bundleIdValue}/members`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrf,
        "Accept": "text/vnd.turbo-stream.html, text/html"
      },
      body: formData
    })

    if (!response.ok) return

    const contentType = response.headers.get("content-type") || ""
    if (contentType.includes("turbo-stream")) {
      const body = await response.text()
      window.Turbo?.renderStreamMessage(body)
    } else {
      // Bundle show controller currently redirects after create —
      // reload to pick up the new member row + regenerated cover.
      window.location.reload()
    }
  }
}
