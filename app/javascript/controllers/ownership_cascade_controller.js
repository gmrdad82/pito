import { Controller } from "@hotwired/stimulus"

// 2026-05-18 — ownership cascade for the per-platform ownership matrix
// on `/games/:id`. Wraps the matrix block rendered by
// `Game::OwnershipMatrixComponent` and applies the same cascade rules
// the server-side `Games::OwnershipTogglesController` enforces, so the
// user sees the cascade IMMEDIATELY (without waiting for the PATCH +
// redirect round-trip) while the DB still converges to the same state.
//
// Rules (mirror the controller):
//
//   1. flipping `played` ON for platform X
//        - deselects every other platform's `played` checkbox
//        - auto-checks `owned` for platform X (a played platform must
//          also be owned)
//      both side-effects requestSubmit() their own form so the server
//      receives the matching PATCHes.
//
//   2. flipping `owned` OFF for platform X
//        - auto-unchecks `played` for platform X if it was currently
//          played (you can't be playing on a platform you no longer
//          own)
//      requestSubmit() the played form so the server clears the
//      played pointer too.
//
// Auto-submit posture: the same checkbox already carries
// `change->auto-submit#submit`, so each cascade-triggered
// `cb.checked = ...` is followed by `cb.closest("form").requestSubmit()`
// — Turbo intercepts the submit, the controller redirects back to
// /games/:id, and the layout-level flash toast surfaces the new state.
//
// JS-disabled clients: the server-side cascade in
// `Games::OwnershipTogglesController` is the authoritative source of
// truth, so a JS-disabled client still gets the right DB state via
// the single PATCH it does fire.
export default class extends Controller {
  static targets = ["owned", "played"]

  playedChanged(event) {
    const cb = event.target
    if (!cb.checked) return
    const slug = cb.dataset.ownershipCascadePlatform

    // Deselect other platforms' played checkboxes and submit their forms.
    this.playedTargets.forEach((other) => {
      if (other.dataset.ownershipCascadePlatform === slug) return
      if (!other.checked) return
      other.checked = false
      this.#syncToggleClass(other, "ownership-matrix__toggle--played")
      const form = other.closest("form")
      if (form && typeof form.requestSubmit === "function") {
        form.requestSubmit()
      }
    })

    // Auto-check owned for this platform if not already checked.
    const ownedForThisPlatform = this.ownedTargets.find(
      (o) => o.dataset.ownershipCascadePlatform === slug,
    )
    if (ownedForThisPlatform && !ownedForThisPlatform.checked) {
      ownedForThisPlatform.checked = true
      this.#syncToggleClass(ownedForThisPlatform, "ownership-matrix__toggle--owned")
      const form = ownedForThisPlatform.closest("form")
      if (form && typeof form.requestSubmit === "function") {
        form.requestSubmit()
      }
    }
  }

  ownedChanged(event) {
    const cb = event.target
    if (cb.checked) return
    const slug = cb.dataset.ownershipCascadePlatform

    const playedForThisPlatform = this.playedTargets.find(
      (p) => p.dataset.ownershipCascadePlatform === slug,
    )
    if (playedForThisPlatform && playedForThisPlatform.checked) {
      playedForThisPlatform.checked = false
      this.#syncToggleClass(playedForThisPlatform, "ownership-matrix__toggle--played")
      const form = playedForThisPlatform.closest("form")
      if (form && typeof form.requestSubmit === "function") {
        form.requestSubmit()
      }
    }
  }

  // Keep the wrapper label's `--owned` / `--played` modifier in sync
  // with the cascaded checkbox state. Without this the green tint
  // would stay stale until the Turbo redirect re-renders the page.
  #syncToggleClass(checkbox, modifierClass) {
    const label = checkbox.closest("label.ownership-matrix__toggle")
    if (!label) return
    if (checkbox.checked) {
      label.classList.add(modifierClass)
    } else {
      label.classList.remove(modifierClass)
    }
  }
}
