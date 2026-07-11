// Pito::HomeTransitionController
//
// Drives the start-screen → conversation transition on first message submit.
//
// Flow:
//   Enter ──► preventDefault + stopImmediatePropagation
//         ──► atomically fix all visible elements to prevent reflow snaps
//         ──► [parallel] choreographed chrome fade-out  +  POST /chat blank (get uuid)
//         ──► chatbox drops straight down (ease-in, accelerates)
//         ──► chatbox expands symmetrically ← → (ease-in: slow start → accelerate)
//             mini-status stays glued — it's inside chatboxArea and rides with it
//         ──► history.pushState /chat/:uuid
//         ──► inject <turbo-cable-stream-source>
//         ──► morph DOM → conversation layout
//         ──► POST the message
//
// After replaceWith() this controller disconnects; subsequent Enter presses
// only fire pito--chat-form#handleKeydown through the normal chat path.

import { Controller } from "@hotwired/stimulus"

// ── Timing constants — edit these to tune the feel ───────────────────────────
const FADE_MS       = 220   // fade/slide duration for chrome elements
const HEAD_START_MS = 80    // logo gets this head start before the rest begin
const CORNER_DELAY  = 60    // extra delay before corners start (after the main group)
const SLIDE_MS      = 240   // chatbox vertical drop
const EXPAND_MS     = 380   // chatbox horizontal expansion (ease-in: slow → fast)

export default class extends Controller {
  static targets = ["logoRow", "tip", "corners", "fade", "chatboxArea", "conversationChrome", "miniStatusSlide"]

  // Dismiss any open sidebar when the start screen or 404 mounts — both render
  // Pito::StartScreen::Component whose root carries data-controller="pito--home-transition".
  connect() {
    window.dispatchEvent(new CustomEvent("pito:resume:dismiss"))
  }

  // ── Entry point ─────────────────────────────────────────────────────────

  async interceptEnter(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    const input = event.target.value?.trim()
    if (!input) return

    event.preventDefault()
    event.stopImmediatePropagation()

    const [, data] = await Promise.all([
      this.#runAnimation(),
      this.#createConversation(),
    ])

    history.pushState({}, "", `/chat/${data.uuid}`)
    document.title = "pito"
    this.#injectTurboStream(data.signed_stream_name)
    this.#morphToConversation(data.uuid)
    this.#postMessage(input, data.uuid)
  }

  // ── Animation ─────────────────────────────────────────────────────────────

  async #runAnimation() {
    const chatbox = this.chatboxAreaTarget

    // Step 1: capture positions BEFORE any DOM change.
    const chatboxRect = chatbox.getBoundingClientRect()
    const fixableEls  = [
      ...this.logoRowTargets,
      ...this.tipTargets,
      ...this.cornersTargets,
    ]
    const savedRects = fixableEls.map(el => ({ el, rect: el.getBoundingClientRect() }))

    // Step 2: atomically fix ALL visible animated elements at their current
    // positions. Doing this in one batch means zero reflow — nothing left in
    // the normal flow can shift.
    const pin = (el, rect) => {
      el.style.position   = "fixed"
      el.style.top        = `${rect.top}px`
      el.style.left       = `${rect.left}px`
      el.style.width      = `${rect.width}px`
      el.style.height     = `${rect.height}px`  // preserve natural height; prevents flex-1 collapse
      el.style.margin     = "0"
      el.style.zIndex     = "100"
      el.style.transition = "none"
      // Only inline elements need display:block to be positionable; setting it on
      // div/flex elements would strip their own display (flex, etc.) causing jumps.
      if (el.tagName === "SPAN") el.style.display = "block"
    }
    savedRects.forEach(({ el, rect }) => pin(el, rect))
    pin(chatbox, chatboxRect)

    // Single forced reflow commits every fixed position in one paint cycle.
    chatbox.getBoundingClientRect()

    // Choreographed chrome fade-out (logo first, rest staggered).
    await this.#fadeOutChrome()

    // Drop straight down (ease-in — accelerates toward the bottom).
    const targetTop = window.innerHeight - chatboxRect.height - 32
    chatbox.getBoundingClientRect()
    chatbox.style.transition = `top ${SLIDE_MS}ms cubic-bezier(0.4,0,1,1)`
    chatbox.style.top = `${targetTop}px`
    await this.#wait(SLIDE_MS)

    // Remove max-width from chatboxArea so it can expand beyond 600px.
    chatbox.style.maxWidth = "none"

    // Expand symmetrically ← →.
    // Re-anchor to center (no transition — was already centered) so animating
    // only `width` makes both edges move outward equally.
    // Easing: ease-in (slow start → accelerates) to match the drop feel.
    // Land at the EXACT width the form will have inside the conversation's
    // .pito-conversation-col so the replaceWith morph causes zero snap:
    // desktop (md+, ≥768px) = the full 964px border box — the col's 5px
    // insets are REMOVED there, so subtracting them
    // left the chatbox 10px narrower than the turns;
    // mobile = full width minus the col's 5px inset each side.
    // (The original full-viewport innerWidth − 100 target predates the
    // centered column entirely.)
    const COL_MAX = 964  // .pito-conversation-col max-width (border box)
    const desktop = window.innerWidth >= 768
    const targetWidth = desktop
      ? Math.min(COL_MAX, window.innerWidth)
      : window.innerWidth - 10
    chatbox.getBoundingClientRect()
    chatbox.style.transition = "none"
    chatbox.style.left       = "50%"
    chatbox.style.transform  = "translateX(-50%)"
    chatbox.getBoundingClientRect()
    chatbox.style.transition = `width ${EXPAND_MS}ms cubic-bezier(0.4,0,1,1)`
    chatbox.style.width = `${targetWidth}px`
    await this.#wait(EXPAND_MS)
  }

  // ── Chrome choreography ───────────────────────────────────────────────────

  async #fadeOutChrome() {
    const animate = (targets, dy, delay) => {
      targets.forEach(el => {
        setTimeout(() => {
          el.style.transition    = `opacity ${FADE_MS}ms ease, transform ${FADE_MS}ms ease`
          el.style.opacity       = "0"
          el.style.transform     = `translateY(${dy}px)`
          el.style.pointerEvents = "none"
        }, delay)
      })
    }

    // Logo rows: random duration/delay/distance within bounds on every visit so
    // the dissolve feels unstable and alive rather than a uniform block wipe.
    const rnd = (min, max) => min + Math.random() * (max - min)
    this.logoRowTargets.forEach(el => {
      const dur   = rnd(FADE_MS * 0.65, FADE_MS * 1.35)  // ±35% of base
      const delay = rnd(0, 55)                             // stagger up to 55ms
      const dy    = -rnd(10, 26)                           // slide 10–26px up
      setTimeout(() => {
        el.style.transition    = `opacity ${dur}ms ease, transform ${dur}ms ease`
        el.style.opacity       = "0"
        el.style.transform     = `translateY(${dy}px)`
        el.style.pointerEvents = "none"
      }, delay)
    })
    // After head start: tip slides DOWN (clears the chatbox path), invisible fades.
    animate(this.tipTargets,     +20, HEAD_START_MS)
    this.fadeTargets.forEach(el => {
      setTimeout(() => {
        el.style.transition    = `opacity ${FADE_MS}ms ease`
        el.style.opacity       = "0"
        el.style.pointerEvents = "none"
      }, HEAD_START_MS)
    })
    // Corners last — slides up like the logo but slightly later.
    animate(this.cornersTargets, -10, HEAD_START_MS + CORNER_DELAY)

    await this.#wait(HEAD_START_MS + CORNER_DELAY + FADE_MS)
  }

  // ── Conversation creation ─────────────────────────────────────────────────

  async #createConversation() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    // Blank input + no uuid → chat controller creates the conversation only
    // and returns {uuid, signed_stream_name}. No message is processed here.
    const resp  = await fetch("/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept":        "application/json",
        "X-CSRF-Token":  token,
      },
      body: JSON.stringify({ input: "" }),
    })
    return resp.json()
  }

  // ── Turbo cable subscription ──────────────────────────────────────────────

  #injectTurboStream(signedStreamName) {
    const el = document.createElement("turbo-cable-stream-source")
    el.setAttribute("channel",            "Turbo::StreamsChannel")
    el.setAttribute("signed-stream-name", signedStreamName)
    document.body.appendChild(el)
  }

  // ── DOM morph ─────────────────────────────────────────────────────────────

  #morphToConversation(uuid) {
    // Extract just the form — chatboxArea (and its start-screen mini-status) is discarded.
    const form   = this.chatboxAreaTarget.querySelector("form.chatbox-form")
    const chrome = this.conversationChromeTarget

    // Add uuid hidden field so subsequent chat POSTs carry the conversation id.
    form.prepend(Object.assign(document.createElement("input"), {
      type: "hidden", name: "uuid", value: uuid,
    }))

    // Build conversation layout (scrollback + chrome) — MIRRORS
    // app/views/conversations/show.html.erb so a transition-built page is
    // byte-equivalent to a reloaded one (same classes, paddings, and
    // controllers; the old 50px-padded full-width panel was a legacy copy
    // that drifted from the centered .pito-conversation-col).
    const conversationEl = document.createElement("div")
    conversationEl.className = "flex flex-col"
    conversationEl.style.cssText = "height: 100vh; overflow-x: hidden;"

    const scrollback = document.createElement("div")
    scrollback.id = "pito-scrollback"
    scrollback.className = "pito-thin-scrollbar"
    scrollback.style.cssText = "flex: 1; overflow-y: auto; padding: 32px 5px 20px;"
    scrollback.dataset.controller = "pito--scrollback pito--quick-run pito--cable-health pito--lasthashtag pito--pull-refresh"

    const bottomPanel = document.createElement("div")
    bottomPanel.className = "pito-conversation-col"
    bottomPanel.style.cssText = "padding-bottom: 32px; overflow-x: hidden;"
    bottomPanel.appendChild(form)
    chrome.removeAttribute("style")
    bottomPanel.appendChild(chrome)

    conversationEl.appendChild(scrollback)
    conversationEl.appendChild(bottomPanel)

    // Replace the start-screen root — disconnects home-transition.
    this.element.replaceWith(conversationEl)

    // Signal the audio controller that ctrl+m mute is now active.
    document.body.dataset.audioChatPage = "true"
    document.dispatchEvent(new CustomEvent("pito:chat-page-ready"))

    // Ensure hidden channel/period inputs exist so the chat_form controller can
    // cycle them (shift+tab / shift+space) and POSTs carry the scope params.
    // NOTE: the old filter-LINE injection that lived here is gone — no
    // server page renders `#pito-chatbox-filter` since the meta moved into the
    // hint slot, so the morph was appending a dead element whose empty
    // shell still carried `.pito-chatbox__filter`'s 10px margin-top, leaving
    // the transition-built chatbox 10px taller than a reloaded one.
    const chatboxArea = this.chatboxAreaTarget
    const authenticated = chatboxArea.dataset.authenticated === "true"
    if (authenticated) {
      if (!form.querySelector('input[name="channel"]')) {
        form.appendChild(Object.assign(document.createElement("input"), {
          type: "hidden", name: "channel", value: "@all",
        }))
      }
      if (!form.querySelector('input[name="period"]')) {
        form.appendChild(Object.assign(document.createElement("input"), {
          type: "hidden", name: "period", value: "7d",
        }))
      }
    }

    // Animate the full mini status sliding in from the right after the chatbox
    // has reached its full width. The auth indicator is already visible from the
    // start screen; the rest of the bar joins it with a 300 ms ease-out slide.
    const miniStatus = conversationEl.querySelector('[data-pito--home-transition-target="miniStatusSlide"]')
    if (miniStatus) {
      miniStatus.style.transition = "none"
      miniStatus.style.transform  = "translateX(100%)"
      miniStatus.style.opacity  = "0"
      miniStatus.getBoundingClientRect()

      miniStatus.style.transition = "transform 300ms ease-out, opacity 300ms ease-in"
      miniStatus.style.transform  = "translateX(0)"
      miniStatus.style.opacity    = "1"
    }
  }

  // ── Submit the message ────────────────────────────────────────────────────

  #postMessage(input, uuid) {
    const form        = document.querySelector("form.chatbox-form")
    const hiddenInput = form.querySelector('[data-pito--chat-form-target="hiddenInput"]')
    const textarea    = form.querySelector('[data-pito--chat-form-target="inputField"]')

    hiddenInput.value = input
    form.requestSubmit()
    textarea.value = ""
    textarea.dispatchEvent(new Event("input", { bubbles: true }))
    document.dispatchEvent(new CustomEvent("pito:submitted"))
  }

  // ── util ──────────────────────────────────────────────────────────────────

  #wait(ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
  }
}
