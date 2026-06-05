// pito--logout
//
// Exact reverse of home_transition_controller's forward animation:
//
//   Forward:  chrome fades → chatbox drops → chatbox expands → filter/mini-status slide in
//   Reverse:  mini-status + filter + scrollback fade out → chatbox shrinks → chatbox rises → navigate "/"
//
// Timing mirrors home_transition_controller (SLIDE_MS / EXPAND_MS / filter 250ms / mini-status 300ms).

import { Controller } from "@hotwired/stimulus"

const SLIDE_IN_MS = 300   // matches mini-status slide-in (longest of the two slide-ins)
const SHRINK_MS   = 380   // mirrors EXPAND_MS
const RISE_MS     = 240   // mirrors SLIDE_MS

export default class extends Controller {
  connect() {
    this.#runReverseAnimation().then(() => Turbo.visit("/"))
  }

  async #runReverseAnimation() {
    // ── Step 1 (parallel): slide mini-status out right, slide filter down, fade scrollback ──
    // Reverses the two "slide in" animations that ran after the DOM morph.

    const miniStatus = document.querySelector('[data-pito--home-transition-target="miniStatusSlide"]')
    const filterEl   = document.querySelector(".pito-chatbox__filter")
    const scrollback = document.getElementById("pito-scrollback")

    if (miniStatus) {
      miniStatus.style.transition = `transform ${SLIDE_IN_MS}ms ease-in, opacity ${SLIDE_IN_MS}ms ease-in`
      miniStatus.style.transform  = "translateX(100%)"
      miniStatus.style.opacity    = "0"
    }

    if (filterEl) {
      filterEl.style.transition = `transform 250ms ease-in, opacity 250ms ease-in`
      filterEl.style.transform  = "translateY(8px)"
      filterEl.style.opacity    = "0"
    }

    if (scrollback) {
      scrollback.style.transition    = `opacity ${SLIDE_IN_MS}ms ease`
      scrollback.style.opacity       = "0"
      scrollback.style.pointerEvents = "none"
    }

    await this.#wait(SLIDE_IN_MS)

    // ── Step 2: shrink chatbox horizontally ────────────────────────────────────
    // Mirrors the expand step: re-anchor to center, animate width only so both
    // edges collapse inward symmetrically. ease-out = reverse of the ease-in expand.

    const form      = document.querySelector("form.chatbox-form")
    const chatboxArea = form?.parentElement
    if (!chatboxArea) return

    const rect = chatboxArea.getBoundingClientRect()

    // Fix to exact current position first (no jump).
    chatboxArea.style.position   = "fixed"
    chatboxArea.style.top        = `${rect.top}px`
    chatboxArea.style.left       = `${rect.left}px`
    chatboxArea.style.width      = `${rect.width}px`
    chatboxArea.style.height     = `${rect.height}px`
    chatboxArea.style.margin     = "0"
    chatboxArea.style.zIndex     = "100"
    chatboxArea.style.transition = "none"
    chatboxArea.getBoundingClientRect()

    // Re-anchor to center (no transition) so the shrink is symmetric ← →.
    chatboxArea.style.left      = "50%"
    chatboxArea.style.transform = "translateX(-50%)"
    chatboxArea.getBoundingClientRect()

    const targetWidth = Math.min(600, window.innerWidth - 64)
    chatboxArea.style.transition = `width ${SHRINK_MS}ms cubic-bezier(0,0,0.6,1)`
    chatboxArea.style.width = `${targetWidth}px`
    await this.#wait(SHRINK_MS)

    // ── Step 3: rise to vertical center ───────────────────────────────────────
    // Mirrors the drop step. ease-out = reverse of the ease-in drop.

    const targetTop = (window.innerHeight - rect.height) / 2
    chatboxArea.style.transition = `top ${RISE_MS}ms cubic-bezier(0,0,0.6,1)`
    chatboxArea.style.top = `${targetTop}px`
    await this.#wait(RISE_MS)
  }

  #wait(ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
  }
}
