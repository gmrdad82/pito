// pito--push-registration
//
// FCM push, web slice (W1). Bridges to the native "push-registration"
// component the Android shell (Hotwire Native) registers: on connect we ask
// native for the device's FCM token via the bridge message "register" (empty
// data), and — ONLY if native replies — POST the token to the existing
// authenticated POST /device_tokens endpoint. Native never handles cookies;
// the web side makes the authenticated call, same as every other pito fetch.
//
// Native silence is a valid outcome, not an error: if permission was denied
// or Firebase isn't configured in that build, native NEVER replies to
// "register" — the callback simply never fires, so this controller does
// nothing further. No timeout, no retry, nothing user-visible either way;
// a failed registration must never surface in the chat UI (console.debug
// only, for local debugging).
//
// Mounted ONLY inside the Hotwire Native shell (see
// ApplicationController#hotwire_native_app? / application.html.erb) — a
// bridge component is inert in a plain browser, and BridgeComponent#send
// silently no-ops there anyway, but there is no reason to ask.

import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

export default class extends BridgeComponent {
  static component = "push-registration"

  connect() {
    super.connect()

    this.send("register", {}, (message) => this.#register(message))
  }

  async #register(message) {
    const token = message?.data?.token
    if (!token) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const resp = await fetch("/device_tokens", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
        },
        credentials: "same-origin",
        body: JSON.stringify({ token }),
      })

      if (!resp.ok) console.debug("pito--push-registration: device_tokens responded", resp.status)
    } catch (error) {
      // Never let a registration failure surface in the chat UI.
      console.debug("pito--push-registration: registration failed", error)
    }
  }
}
