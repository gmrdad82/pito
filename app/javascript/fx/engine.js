// The living background's CONTEXT ENGINE (2.1.0 P4) — a pure state machine:
// no DOM, no canvas, no clock of its own (vitest-covered end to end).
//
//   dominance in ──▶ hysteresis ──▶ seeded pick ──▶ crossfade mix out
//
// • observeDominant(view) is fed by the viewport listener with the current
//   dominant message's {context, eventId, covers} (or null = the sky).
// • A candidate must HOLD dominance for hysteresis_ms before anything moves
//   (F6 — scrolling glides, never strobes).
// • The pick is SEEDED by event id (F8): the same message keeps its effect
//   across scrolls forever; the same command in new messages re-rolls.
// • COVER-KEYED CACHE (owner 2026-07-13): a COVERED mood's identity is
//   name+covers, not the event. A new dominant message whose covers match
//   the LIVING mood's covers keeps it untouched — no re-roll, no reinstate,
//   no crossfade — as long as the effect is viable in the new context's
//   pool ("show vid 2" water flows seamlessly into "analyze vid 2", and
//   into "show game 333" when they share the cover). A different cover is
//   a fresh mood — and COVER-LESS moods (plasma, smoke on AI answers) stay
//   per-message: two AI messages both rolling plasma re-instate (owner).
//   NEIGHBOUR-ONLY (owner): the cache is the LIVING mood and nothing else —
//   once a different mood takes over, history is gone; a later message
//   with the first cover starts a fresh mood, never resurrects the old one.
// • Pool entries degrade honestly: an effect whose covers cardinality (single
//   needs 1+, many needs 2+) isn't met by the view's covers, needs_float
//   without the extension, or no registered renderer is skipped; an empty
//   surviving pool means the sky answers (F1).
// • contexts[name] is { covers, pool: [{effect, weight}] } — the CONTEXT's
//   own covers cardinality is enforced at boot by the Ruby registry; the pool
//   is what pickFor/cachedTarget walk here.
// • tick(now) returns the mix: { skyAlpha, enforcer: {name, covers, alpha,
//   eventId} | null }. Crossfades are linear over crossfade_ms — the
//   renderer layer maps alphas to paint.

import { fnv1a } from "fx/sky"

export function createEngine({ config, capabilities = {}, renderers = {} }) {
  const engine = config?.engine || {}
  const effects = config?.effects || {}
  const contexts = config?.contexts || {}
  const hysteresisMs = engine.hysteresis_ms ?? 300
  const crossfadeMs = engine.crossfade_ms ?? 700

  // active/target: null = the resting sky, or {name, covers, eventId}
  let active = null
  let candidate = null // {view, since}
  let transition = null // {from, to, startedAt}

  // An effect survives the pool filter only if the page can actually run it.
  // covers cardinality is the honest runtime degrade for missing art — the
  // single/many CONTEXT gating itself is enforced at boot by the Ruby registry.
  function viable(name, covers) {
    const def = effects[name]
    if (!def) return false
    if (!renderers[name]) return false
    const n = covers ? covers.length : 0
    if (def.covers === "single" && n < 1) return false
    // A many-cover effect may set its own floor (cover_wall: 5, owner —
    // below it the wall reads as a few lost stamps); 2 is the generic law.
    const manyMin = (def.knobs && def.knobs.min_covers) || 2
    if (def.covers === "many" && n < manyMin) return false
    if (def.needs_float && !capabilities.float) return false
    if (def.engine === "webgl" && !capabilities.webgl) return false
    return true
  }

  // Deterministic weighted pick, seeded by the event id (F8). excludeName
  // implements the ANTI-REPEAT rule (owner: consecutive different-cover
  // messages must not wear the same effect — cyberpunk water then stellar
  // blade water reads as one lazy mood): the living effect is dropped from
  // the pool when alternatives exist; a one-effect pool (vid = water only)
  // legitimately repeats.
  function pickFor(eventId, context, covers, excludeName = null) {
    let pool = ((contexts[context] && contexts[context].pool) || []).filter((e) => viable(e.effect, covers))
    if (excludeName) {
      const others = pool.filter((e) => e.effect !== excludeName)
      if (others.length > 0) pool = others
    }
    if (pool.length === 0) return null
    const total = pool.reduce((sum, e) => sum + e.weight, 0)
    let roll = fnv1a(`fx:${eventId}:${context}`) % total
    for (const entry of pool) {
      roll -= entry.weight
      if (roll < 0) return entry.effect
    }
    return pool[pool.length - 1].effect
  }

  function coverSig(t) {
    return (t.covers || []).join("|")
  }

  // Identity is WHAT'S VISIBLE (effect + art) for covered moods — two
  // messages wearing the same mood over the same cover are one mood.
  // Cover-less moods keep per-message identity (owner: they re-instate).
  function sameTarget(a, b) {
    if (a === null && b === null) return true
    if (!a || !b) return false
    if (a.name !== b.name) return false
    const sig = coverSig(a)
    if (sig !== coverSig(b)) return false
    return sig !== "" || a.eventId === b.eventId
  }

  // The cover-keyed cache: keep the LIVING mood for a new view when the art
  // matches and the new context's pool still carries the effect. Neighbour-
  // only by construction — it never looks past the active/incoming mood.
  function cachedTarget(view) {
    if (!view.covers || view.covers.length === 0) return null
    const current = transition ? transition.to : active
    if (!current) return null
    if (coverSig(current) !== coverSig({ covers: view.covers })) return null
    const pool = (contexts[view.context] && contexts[view.context].pool) || []
    const stillOffered = pool.some((e) => e.effect === current.name && viable(e.effect, view.covers))
    return stillOffered ? current : null
  }

  function beginTransition(to, now) {
    if (sameTarget(active, to)) return
    transition = { from: active, to, startedAt: now }
  }

  return {
    // The viewport listener's single entry point. view = {context, eventId,
    // covers} for the dominant eligible message, or null for "sky moment".
    observeDominant(view, now) {
      const target = view
        ? cachedTarget(view) ||
          (() => {
            // Fresh pick — avoid repeating the living effect when the art
            // changed (anti-repeat; same-cover continuity was handled above).
            const current = transition ? transition.to : active
            const avoid =
              current && coverSig(current) !== coverSig({ covers: view.covers })
                ? current.name
                : null
            const name = pickFor(view.eventId, view.context, view.covers, avoid)
            return name ? { name, covers: view.covers || [], eventId: view.eventId } : null
          })()
        : null

      if (sameTarget(target, transition ? transition.to : active)) {
        candidate = null
        return
      }
      if (!candidate || !sameTarget(candidate.target, target)) {
        candidate = { target, since: now }
      }
      if (now - candidate.since >= hysteresisMs) {
        beginTransition(candidate.target, now)
        candidate = null
      }
    },

    // The frame mix. Linear crossfade; when it completes, the target becomes
    // active. skyAlpha is the complement of the enforcer's presence (F4 —
    // the renderer skips the sky pass entirely at skyAlpha 0).
    tick(now) {
      // Candidates mature on the CLOCK, not only on observe calls — once
      // scrolling settles, no further dominance events arrive, and a
      // candidate must still cross its hysteresis into the crossfade.
      if (candidate && now - candidate.since >= hysteresisMs) {
        beginTransition(candidate.target, now)
        candidate = null
      }
      if (transition) {
        const t = Math.min(1, (now - transition.startedAt) / crossfadeMs)
        const from = transition.from
        const to = transition.to
        if (t >= 1) {
          active = to
          transition = null
        } else {
          const rising = to ? t : 0
          const falling = from ? 1 - t : 0
          const enforcer = to
            ? { ...to, alpha: rising }
            : from
              ? { ...from, alpha: falling }
              : null
          return {
            skyAlpha: 1 - Math.max(rising, falling),
            enforcer,
            fading: from && to ? { ...from, alpha: 1 - t } : null,
          }
        }
      }
      return {
        skyAlpha: active ? 0 : 1,
        enforcer: active ? { ...active, alpha: 1 } : null,
        fading: null,
      }
    },

    // Introspection for tests + the FPS meter's future detail line.
    state() {
      return { active, candidate, transition }
    },

    pickFor,
  }
}
