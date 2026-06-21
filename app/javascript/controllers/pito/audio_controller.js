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
// Sound is gated on soundEnabled() evaluated at play time so a live settings
// change (e.g. /config sound off) takes effect without a page reload.

import { Controller } from "@hotwired/stimulus"
import { soundEnabled } from "pito/settings"

const SEND_SRC      = "/sounds/send.mp3"
const RECEIVE_SRC   = "/sounds/receive.mp3"
const NOTIFY_SRC    = "/sounds/notify.mp3"
const RECEIVE_DEBOUNCE_MS = 400  // ms of silence before we consider the turn done
const NOTIFY_DEBOUNCE_MS  = 400  // burst of arriving notifs collapses to one sound

export default class extends Controller {
  connect() {
    this.#preload()
    this.#bindEvents()
  }

  disconnect() {
    this.abort?.abort()
    this.#clearPending()
  }

  // ── internals ──────────────────────────────────────────────────────────────

  #preload() {
    this.sendAudio    = new Audio(SEND_SRC)
    this.receiveAudio = new Audio(RECEIVE_SRC)
    this.notifyAudio  = new Audio(NOTIFY_SRC)
  }

  #playSend() {
    if (!soundEnabled()) return
    this.#clearPending()
    this.#playNow(this.sendAudio)
    this.sendUntil = Date.now() + (this.sendAudio.duration * 1000 || 80)
  }

  #scheduleReceive() {
    if (!soundEnabled()) return
    clearTimeout(this.receiveTimer)
    this.receiveTimer = setTimeout(() => {
      if (!soundEnabled()) return
      const delay = Math.max(0, this.sendUntil - Date.now())
      setTimeout(() => {
        if (soundEnabled()) this.#playNow(this.receiveAudio)
      }, delay)
    }, RECEIVE_DEBOUNCE_MS)
  }

  #playNow(audio) {
    audio.currentTime = 0
    audio.play()?.catch(() => {
      // Browsers block autoplay until the first user gesture.
    })
  }

  #scheduleNotify() {
    if (!soundEnabled()) return
    clearTimeout(this.notifyTimer)
    this.notifyTimer = setTimeout(() => {
      if (soundEnabled()) this.#playNow(this.notifyAudio)
    }, NOTIFY_DEBOUNCE_MS)
  }

  #clearPending() {
    clearTimeout(this.receiveTimer)
    this.receiveTimer = null
    clearTimeout(this.notifyTimer)
    this.notifyTimer = null
  }

  #bindEvents() {
    this.abort = new AbortController()
    document.addEventListener("pito:submitted",             () => this.#playSend(),        { signal: this.abort.signal })
    document.addEventListener("pito:result-appended",       () => this.#scheduleReceive(), { signal: this.abort.signal })
    document.addEventListener("pito:notification-arrived",  () => this.#scheduleNotify(),  { signal: this.abort.signal })
  }
}
