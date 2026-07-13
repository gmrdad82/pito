import { describe, it, expect } from "vitest"
import { createEngine } from "fx/engine"

const CONFIG = {
  engine: { fps: 30, dpr_cap: 1, crossfade_ms: 700, hysteresis_ms: 300 },
  effects: {
    sky: { engine: "canvas", covers: "none", needs_float: false, tint_source: "fixed" },
    plasma: { engine: "webgl", covers: "none", needs_float: false, tint_source: "theme" },
    duotone: { engine: "webgl", covers: "single", needs_float: false, tint_source: "cover" },
    water: { engine: "webgl", covers: "single", needs_float: true, tint_source: "cover" },
    cover_wall: { engine: "css", covers: "many", needs_float: false, tint_source: "cover" },
  },
  contexts: {
    game_detail: {
      covers: "single",
      pool: [
        { effect: "duotone", weight: 3 },
        { effect: "water", weight: 3 },
        { effect: "plasma", weight: 1 },
      ],
    },
    vid: { covers: "single", pool: [{ effect: "water", weight: 1 }] },
    analyze: {
      covers: "single",
      pool: [
        { effect: "plasma", weight: 1 },
        { effect: "water", weight: 2 },
      ],
    },
    ai: { covers: "none", pool: [{ effect: "plasma", weight: 1 }] },
    default: { covers: "none", pool: [{ effect: "sky", weight: 1 }] },
    list: { covers: "many", pool: [{ effect: "cover_wall", weight: 1 }] },
  },
}

const ALL = { webgl: true, float: true }
const RENDERERS = { plasma: {}, duotone: {}, water: {}, cover_wall: {} }

function engineWith(overrides = {}) {
  return createEngine({ config: CONFIG, capabilities: ALL, renderers: RENDERERS, ...overrides })
}

const view = (eventId, context = "game_detail", covers = ["/c.jpg"]) => ({ context, eventId, covers })

describe("the fx context engine", () => {
  it("rests on the sky until a candidate HOLDS dominance for hysteresis_ms", () => {
    const e = engineWith()
    e.observeDominant(view(1), 0)
    expect(e.tick(100)).toMatchObject({ skyAlpha: 1, enforcer: null })

    e.observeDominant(view(1), 299)
    expect(e.state().transition).toBeNull() // 299ms held — not yet

    e.observeDominant(view(1), 301)
    expect(e.state().transition).not.toBeNull() // held past 300ms — moving
  })

  it("matures a held candidate on the CLOCK alone (no further observe calls)", () => {
    const e = engineWith()
    e.observeDominant(view(1), 0) // one observation, then silence
    expect(e.tick(200).enforcer).toBeNull()
    const later = e.tick(400) // past hysteresis purely by time
    expect(e.state().transition || later.enforcer).toBeTruthy()
  })

  it("re-arms hysteresis when the candidate changes mid-hold (scroll glide, no strobe)", () => {
    const e = engineWith()
    e.observeDominant(view(1), 0)
    e.observeDominant(view(2), 200) // different message before the hold matured
    e.observeDominant(view(2), 400) // 2 has only held 200ms
    expect(e.state().transition).toBeNull()
    e.observeDominant(view(2), 501)
    expect(e.state().transition).not.toBeNull()
  })

  it("crossfades linearly over crossfade_ms and completes", () => {
    const e = engineWith()
    e.observeDominant(view(1), 0)
    e.observeDominant(view(1), 300) // transition begins at 300

    const mid = e.tick(650) // 350/700 through
    expect(mid.enforcer.alpha).toBeCloseTo(0.5, 1)
    expect(mid.skyAlpha).toBeCloseTo(0.5, 1)

    const done = e.tick(1100)
    expect(done.enforcer.alpha).toBe(1)
    expect(done.skyAlpha).toBe(0) // occlusion: the sky pass may skip (F4)
  })

  it("keeps the SAME pick for the same event forever (F8 seeded stability)", () => {
    const e = engineWith()
    const first = e.pickFor(42, "game_detail", ["/c.jpg"])
    for (let i = 0; i < 20; i++) expect(e.pickFor(42, "game_detail", ["/c.jpg"])).toBe(first)
  })

  it("varies picks across different events from the same pool (not 1:1)", () => {
    const e = engineWith()
    const picks = new Set()
    for (let id = 0; id < 40; id++) picks.add(e.pickFor(id, "game_detail", ["/c.jpg"]))
    expect(picks.size).toBeGreaterThan(1)
  })

  it("degrades pool entries honestly: no covers → cover effects out", () => {
    const e = engineWith()
    for (let id = 0; id < 30; id++) {
      expect(e.pickFor(id, "game_detail", [])).toBe("plasma")
    }
  })

  it("degrades on missing capabilities: no float ext → water out", () => {
    const e = engineWith({ capabilities: { webgl: true, float: false } })
    for (let id = 0; id < 30; id++) {
      expect(e.pickFor(id, "game_detail", ["/c.jpg"])).not.toBe("water")
    }
  })

  it("answers the sky when NOTHING in the pool can run (no webgl at all)", () => {
    const e = engineWith({ capabilities: { webgl: false, float: false } })
    e.observeDominant(view(7), 0)
    e.observeDominant(view(7), 350)
    expect(e.tick(1200)).toMatchObject({ skyAlpha: 1, enforcer: null })
  })

  it("ignores effects with no registered renderer (P4 ships engine-only, sky holds)", () => {
    const e = engineWith({ renderers: {} })
    e.observeDominant(view(9), 0)
    e.observeDominant(view(9), 350)
    expect(e.tick(1200)).toMatchObject({ skyAlpha: 1, enforcer: null })
  })

  it("fades back to the sky when dominance returns to null", () => {
    const e = engineWith()
    e.observeDominant(view(1), 0)
    e.observeDominant(view(1), 300)
    e.tick(1100) // enforcer fully in

    e.observeDominant(null, 1200)
    e.observeDominant(null, 1501) // held null past hysteresis
    const fading = e.tick(1851) // 350/700 back
    expect(fading.enforcer.alpha).toBeCloseTo(0.5, 1)
    expect(fading.skyAlpha).toBeCloseTo(0.5, 1)
    expect(e.tick(2300)).toMatchObject({ skyAlpha: 1, enforcer: null })
  })
  // ── The cover-keyed cache (owner 2026-07-13): mood identity is the ART,
  //    never the message. ──

  // Drive a view all the way to ACTIVE: hold past hysteresis, then let the
  // crossfade complete.
  function activate(e, v, t0 = 0) {
    e.observeDominant(v, t0)
    e.tick(t0 + 301)
    e.tick(t0 + 301 + 701)
    return e.state().active
  }

  it("keeps the living mood untouched when a new message shares its cover (show vid 2 → analyze vid 2)", () => {
    const e = engineWith()
    const before = activate(e, view(2, "vid", ["/covers/a.jpg"]))
    expect(before).toMatchObject({ name: "water" })

    // Same vid, new command, new event — same cover; water is in analyze's pool.
    e.observeDominant(view(9, "analyze", ["/covers/a.jpg"]), 2000)
    e.tick(2400) // past hysteresis — still NOTHING moves
    expect(e.state().transition).toBeNull()
    expect(e.state().active).toBe(before) // the very same mood object — never reinstated
    expect(e.tick(2500)).toMatchObject({ skyAlpha: 0, enforcer: { name: "water", alpha: 1 } })
  })

  it("reinstates the mood for a different cover (show vid 4 after show vid 2)", () => {
    const e = engineWith()
    activate(e, view(2, "vid", ["/covers/a.jpg"]))

    e.observeDominant(view(4, "vid", ["/covers/b.jpg"]), 2000)
    e.tick(2301) // hysteresis held → a real crossfade begins
    expect(e.state().transition).not.toBeNull()
    e.tick(2301 + 701)
    expect(e.state().active).toMatchObject({ name: "water", covers: ["/covers/b.jpg"] })
  })

  it("keeps the mood across entities sharing the art (show game 333 after show vid 2, linked)", () => {
    const e = engineWith()
    const before = activate(e, view(2, "vid", ["/covers/game333.jpg"]))
    expect(before).toMatchObject({ name: "water" })

    // The game detail's pool offers water too — the shared cover keeps the
    // living ripple field, even though a fresh seeded roll might have picked
    // duotone for this event.
    e.observeDominant(view(333, "game_detail", ["/covers/game333.jpg"]), 3000)
    e.tick(3400)
    expect(e.state().transition).toBeNull()
    expect(e.state().active).toBe(before)
  })

  it("re-rolls when the cover matches but the new pool no longer offers the effect", () => {
    const e = engineWith()
    const before = activate(e, view(2, "vid", ["/covers/a.jpg"]))
    expect(before).toMatchObject({ name: "water" })

    // The ai pool carries only plasma — the cache cannot hold water there.
    e.observeDominant(view(7, "ai", ["/covers/a.jpg"]), 2000)
    e.tick(2301)
    expect(e.state().transition).not.toBeNull()
  })

  it("re-instates cover-less moods per message (two AI plasmas restart, owner)", () => {
    const e = engineWith()
    const first = activate(e, view(7, "ai", []))
    expect(first).toMatchObject({ name: "plasma" })

    e.observeDominant(view(8, "ai", []), 3000)
    e.tick(3301) // a NEW plasma crossfades in — no cover, no cache
    expect(e.state().transition).not.toBeNull()
  })

  it("caches NEIGHBOURS only — an old cover returning later starts fresh (owner's 4-step sequence)", () => {
    const e = engineWith()
    // show vid 2 → water over cover A
    const waterA = activate(e, view(2, "vid", ["/covers/a.jpg"]))
    expect(waterA).toMatchObject({ name: "water" })

    // analyze vid 2 → neighbour, same cover: kept
    e.observeDominant(view(9, "analyze", ["/covers/a.jpg"]), 2000)
    e.tick(2400)
    expect(e.state().active).toBe(waterA)

    // show vid 4 → different cover: fresh water B takes over
    e.observeDominant(view(4, "vid", ["/covers/b.jpg"]), 4000)
    e.tick(4301)
    e.tick(4301 + 701)
    expect(e.state().active).toMatchObject({ covers: ["/covers/b.jpg"] })

    // show game 333 → cover A AGAIN, but the living mood is water B: the old
    // water-A mood is history — a real transition to a FRESH mood begins.
    e.observeDominant(view(333, "game_detail", ["/covers/a.jpg"]), 8000)
    e.tick(8301)
    expect(e.state().transition).not.toBeNull()
    expect(e.state().transition.to).not.toBe(waterA)
  })

  it("never repeats the living effect for a different cover (owner: cyberpunk water → stellar blade water)", () => {
    for (let seed = 1; seed <= 20; seed++) {
      const e = engineWith()
      const first = activate(e, view(seed, "game_detail", ["/covers/cyberpunk.jpg"]))
      e.observeDominant(view(seed + 1000, "game_detail", ["/covers/stellar.jpg"]), 5000)
      e.tick(5301)
      const next = e.state().transition?.to || e.state().active
      expect(next.name).not.toBe(first.name)
    }
  })

  it("still repeats honestly when the pool offers nothing else (vid = water only)", () => {
    const e = engineWith()
    activate(e, view(2, "vid", ["/covers/a.jpg"]))
    e.observeDominant(view(4, "vid", ["/covers/b.jpg"]), 5000)
    e.tick(5301)
    expect(e.state().transition.to).toMatchObject({ name: "water", covers: ["/covers/b.jpg"] })
  })

  it("requires 2+ covers for a 'many' effect: sky holds with one cover, cover_wall lands with two (list context)", () => {
    expect(engineWith().pickFor(50, "list", ["/covers/a.jpg"])).toBeNull()
    expect(engineWith().pickFor(50, "list", ["/covers/a.jpg", "/covers/b.jpg"])).toBe("cover_wall")

    const single = engineWith()
    single.observeDominant(view(50, "list", ["/covers/a.jpg"]), 0)
    single.observeDominant(view(50, "list", ["/covers/a.jpg"]), 350)
    expect(single.tick(1200)).toMatchObject({ skyAlpha: 1, enforcer: null })

    const many = activate(engineWith(), view(51, "list", ["/covers/a.jpg", "/covers/b.jpg"]))
    expect(many).toMatchObject({ name: "cover_wall" })
  })

  it("honors a many-effect's own min_covers floor (owner: walls need 5+)", () => {
    const config = JSON.parse(JSON.stringify(CONFIG))
    config.effects.cover_wall.knobs = { min_covers: 5 }
    const e = createEngine({ config, capabilities: ALL, renderers: { ...RENDERERS, cover_wall: {} } })
    const four = ["/a.jpg", "/b.jpg", "/c.jpg", "/d.jpg"]
    expect(e.pickFor(1, "list", four)).toBeNull()
    expect(e.pickFor(1, "list", [...four, "/e.jpg"])).toBe("cover_wall")
  })

})
