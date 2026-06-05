// spec/javascript/reveal_queue.test.js
//
// Tests for pito/reveal_queue.js
//
// Key invariants:
//   1. Jobs run in FIFO order.
//   2. A thrown/rejected reveal does NOT block later jobs (the .catch fix).
//   3. Backpressure (>CAP waiting) calls the job with { instant: true }.

import { describe, it, expect, vi, beforeEach } from "vitest"

// reveal_queue.js is a module-level singleton; we reload it fresh for each
// test by resetting the module registry between tests.
describe("reveal_queue", () => {
  // Re-import a fresh module before each test so state is clean.
  let enqueue

  beforeEach(async () => {
    vi.resetModules()
    const mod = await import("pito/reveal_queue")
    enqueue = mod.enqueue
  })

  // ── FIFO order ──────────────────────────────────────────────────────────────

  it("runs jobs in FIFO order", async () => {
    const order = []

    const job1 = enqueue(() => { order.push(1); return Promise.resolve() })
    const job2 = enqueue(() => { order.push(2); return Promise.resolve() })
    const job3 = enqueue(() => { order.push(3); return Promise.resolve() })

    await Promise.allSettled([job1, job2, job3])

    expect(order).toEqual([1, 2, 3])
  })

  // ── Error isolation ─────────────────────────────────────────────────────────

  it("a rejected reveal does not block later jobs", async () => {
    const ran = []

    // Job 1 rejects.
    const job1 = enqueue(() => Promise.reject(new Error("boom")))
    // Job 2 should still run.
    const job2 = enqueue(() => { ran.push("job2"); return Promise.resolve() })

    // job1 itself rejects (enqueue forwards the original promise).
    await expect(job1).rejects.toThrow("boom")

    // job2 must complete successfully.
    await job2

    expect(ran).toEqual(["job2"])
  })

  it("a synchronously-thrown reveal does not block later jobs", async () => {
    const ran = []

    const job1 = enqueue(() => { throw new Error("sync boom") })
    const job2 = enqueue(() => { ran.push("after throw"); return Promise.resolve() })

    await expect(job1).rejects.toThrow("sync boom")
    await job2

    expect(ran).toEqual(["after throw"])
  })

  // ── Backpressure ────────────────────────────────────────────────────────────
  //
  // CAP = 3 (from reveal_queue.js).  When more than 3 jobs are already waiting
  // the next one is called with { instant: true }.

  it("calls jobs with { instant: false } while under the cap", async () => {
    const opts = []

    // Enqueue 2 fast jobs (CAP=3, so neither triggers instant mode).
    const j1 = enqueue((o) => { opts.push(o); return Promise.resolve() })
    const j2 = enqueue((o) => { opts.push(o); return Promise.resolve() })

    await Promise.all([j1, j2])

    expect(opts).toHaveLength(2)
    opts.forEach((o) => expect(o.instant).toBe(false))
  })

  it("calls job with { instant: true } when > CAP jobs are waiting", async () => {
    // We need >3 jobs waiting simultaneously.  The first job blocks the chain;
    // we enqueue 4 more while it is blocked, so waiting=4 when the 5th is added.
    let unblock
    const blocker = new Promise((res) => { unblock = res })

    // Job 0: blocks the chain until we call unblock().
    enqueue(() => blocker)

    // Enqueue CAP+1 (=4) more jobs while the blocker is holding — waiting will
    // be 1,2,3,4 for each; the 4th exceeds CAP=3.
    const capturedOpts = []
    const jobs = []
    for (let i = 0; i < 4; i++) {
      jobs.push(enqueue((o) => { capturedOpts.push({ i, o }); return Promise.resolve() }))
    }

    // Unblock — let everything drain.
    unblock()
    await Promise.allSettled(jobs)

    // The last job (i=3) must have received instant=true (waiting was 4 > CAP=3).
    const last = capturedOpts.find((x) => x.i === 3)
    expect(last).toBeDefined()
    expect(last.o.instant).toBe(true)
  })
})
