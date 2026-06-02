// Pito::AudioController
//
// Debounced chat sounds with queue management.
//
// Send sound: plays immediately on pito:submitted (only when input is non-empty).
// Receive sound: debounced 400 ms after the LAST pito:result-appended.
//   If new segments keep arriving, the timer resets — the sound only fires
//   when the backend has finished emitting for the turn.
// Overlap guard: if the send sound is still playing, the receive sound waits.
// Queue clearing: a new send immediately cancels any pending receive.
//
// Mute toggle is wired externally (keyboard shortcuts deferred).
// State is persisted in localStorage under "pito:audio-muted".

import { Controller } from "@hotwired/stimulus"

const SEND_SRC      = "/sounds/send.mp3"
const RECEIVE_SRC   = "/sounds/receive.mp3"
const RECEIVE_DEBOUNCE_MS = 400  // ms of silence before we consider the turn done

export default class extends Controller {
  connect() {
    this.muted = localStorage.getItem("pito:audio-muted") === "true"
    this.#preload()
    this.#updateIndicator()
    this.#bindEvents()
  }

  disconnect() {
    this.abort?.abort()
    this.#clearPending()
  }

  // ── public API ─────────────────────────────────────────────────────────────

  toggleMute() {
    this.muted = !this.muted
    localStorage.setItem("pito:audio-muted", String(this.muted))
    if (this.muted) this.#stopAll()
    this.#updateIndicator()
  }

  // ── internals ──────────────────────────────────────────────────────────────

  #preload() {
    this.sendAudio    = new Audio(SEND_SRC)
    this.receiveAudio = new Audio(RECEIVE_SRC)
  }

  #playSend() {
    if (this.muted) return
    this.#clearPending()
    this.#playNow(this.sendAudio)
    this.sendUntil = Date.now() + (this.sendAudio.duration * 1000 || 80)
  }

  #scheduleReceive() {
    if (this.muted) return
    clearTimeout(this.receiveTimer)
    this.receiveTimer = setTimeout(() => {
      const delay = Math.max(0, this.sendUntil - Date.now())
      setTimeout(() => this.#playNow(this.receiveAudio), delay)
    }, RECEIVE_DEBOUNCE_MS)
  }

  #playNow(audio) {
    audio.currentTime = 0
    audio.play().catch(() => {
      // Browsers block autoplay until the first user gesture.
    })
  }

  #stopAll() {
    this.sendAudio.pause()
    this.sendAudio.currentTime = 0
    this.receiveAudio.pause()
    this.receiveAudio.currentTime = 0
    this.#clearPending()
  }

  #clearPending() {
    clearTimeout(this.receiveTimer)
    this.receiveTimer = null
  }

  #updateIndicator() {
    const label = document.getElementById("pito-audio-label")
    if (!label) return
    // "mute" label: dim when active, cyan when muted.
    label.classList.toggle("text-fg-dim", !this.muted)
    label.classList.toggle("text-cyan", this.muted)
  }

  #bindEvents() {
    this.abort = new AbortController()
    document.addEventListener("pito:submitted",       () => this.#playSend(),     { signal: this.abort.signal })
    document.addEventListener("pito:result-appended", () => this.#scheduleReceive(), { signal: this.abort.signal })

    if (this.element.dataset.audioChatPage === "true") {
      this.#bindMuteKey()
    } else {
      document.addEventListener("pito:chat-page-ready", () => this.#bindMuteKey(),
        { signal: this.abort.signal, once: true })
    }
  }

  #bindMuteKey() {
    document.addEventListener("keydown", (e) => {
      if (e.key === "m" && e.ctrlKey) {
        e.preventDefault()
        this.toggleMute()
      }
    }, { signal: this.abort.signal })
  }
}
