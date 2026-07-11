// pito--ai-accent
//
// Flips the chatbox's Segment bar onto the AI gradient accent the moment the
// input starts with the `ai` verb, and back to purple when it doesn't — the
// live start of the visual thread that continues through the `ai …` echo and
// the :ai reply (both render data-accent="ai" server-side).
//
// Mounted on the #pito-chatbox wrapper next to the other chatbox controllers;
// listens on the wrapper's input events (the textarea bubbles them up), so no
// extra targets or actions are declared in the template.

import { Controller } from "@hotwired/stimulus"

const AI_PREFIX = /^\s*@ai\b/i

export default class extends Controller {
  connect() {
    this.abort = new AbortController()
    this.element.addEventListener("input", () => this.#sync(), { signal: this.abort.signal })
    this.#sync()
  }

  disconnect() {
    this.abort?.abort()
  }

  #sync() {
    const bar   = this.element.querySelector(".pito-segment__bar")
    const field = this.element.querySelector("textarea, input[type='text']")
    if (!bar || !field) return

    const ai = AI_PREFIX.test(field.value || "")
    // Only ever toggles between the chatbox's own purple and the ai gradient —
    // never touches other accents (the chatbox bar is purple by construction).
    bar.dataset.accent = ai ? "ai" : "purple"
  }
}
