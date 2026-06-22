// spec/javascript/reveal_queue.test.js
//
// Tests for pito/reveal_queue.js
//
// Key invariants (CONCURRENCY model — K3):
//   1. Jobs run CONCURRENTLY — a job starts immediately and is never blocked
//      behind a slow earlier job (no FIFO).
//   2. A thrown/rejected reveal does NOT affect other jobs (independent), and
//      the returned promise still rejects for the caller (error isolation).
//   3. Backpressure: once MAX_CONCURRENT (=4) reveals are already in flight, the
//      next job is called with { instant: true }.

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

  // ── Concurrency ───────────────────────────────────────────────────────────
  //
  // The headline K3 property: a slow earlier job must NOT block a later one. If
  // jobs were serialised, job2 could not finish until job1 resolved; concurrent
  // jobs let job2 complete while job1 is still pending.

  it("runs jobs concurrently — a slow job does NOT block a later one", async () => {
    let unblock
    const slow = new Promise((res) => { unblock = res })

    let job2Done = false

    // Job 1 is slow (stays pending). Job 2 should complete WITHOUT waiting on it.
    enqueue(() => slow)
    const job2 = enqueue(() => Promise.resolve()).then(() => { job2Done = true })

    await job2
    expect(job2Done).toBe(true) // finished while job1 is still pending

    unblock() // clean up the pending job
  })

  it("starts every job immediately (no FIFO gating)", async () => {
    const started = []

    // Each job records when it STARTS. With concurrency all three start before
    // any of them resolves (none chain on a previous one).
    let unblock1, unblock2, unblock3
    const j1 = enqueue(() => { started.push(1); return new Promise(r => { unblock1 = r }) })
    const j2 = enqueue(() => { started.push(2); return new Promise(r => { unblock2 = r }) })
    const j3 = enqueue(() => { started.push(3); return new Promise(r => { unblock3 = r }) })

    // Let the microtasks that start each revealFn run.
    await Promise.resolve()
    await Promise.resolve()

    expect(started).toEqual([1, 2, 3]) // all started, none waited on another

    unblock1(); unblock2(); unblock3()
    await Promise.allSettled([j1, j2, j3])
  })

  // ── Error isolation ─────────────────────────────────────────────────────────

  it("a rejected reveal does not affect later jobs", async () => {
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

  it("a synchronously-thrown reveal does not affect later jobs", async () => {
    const ran = []

    const job1 = enqueue(() => { throw new Error("sync boom") })
    const job2 = enqueue(() => { ran.push("after throw"); return Promise.resolve() })

    await expect(job1).rejects.toThrow("sync boom")
    await job2

    expect(ran).toEqual(["after throw"])
  })

  // ── Backpressure ────────────────────────────────────────────────────────────
  //
  // MAX_CONCURRENT = 4 (from reveal_queue.js). Once 4 reveals are already in
  // flight, the next is called with { instant: true }.

  it("calls jobs with { instant: false } while under the concurrency cap", async () => {
    const opts = []

    // Two fast jobs — well under the cap of 4, so neither triggers instant mode.
    const j1 = enqueue((o) => { opts.push(o); return Promise.resolve() })
    const j2 = enqueue((o) => { opts.push(o); return Promise.resolve() })

    await Promise.all([j1, j2])

    expect(opts).toHaveLength(2)
    opts.forEach((o) => expect(o.instant).toBe(false))
  })

  it("calls the job with { instant: true } once MAX_CONCURRENT jobs are in flight", async () => {
    // Fill the cap with 4 jobs that stay pending (in flight), so the 5th tips
    // over the concurrency cap and must run instant.
    const unblocks = []
    for (let i = 0; i < 4; i++) {
      enqueue(() => new Promise((r) => unblocks.push(r)))
    }

    let overflowOpt
    const overflow = enqueue((o) => { overflowOpt = o; return Promise.resolve() })

    await overflow
    expect(overflowOpt.instant).toBe(true)

    // Drain the held jobs.
    unblocks.forEach((u) => u())
  })

  it("frees a slot when a job settles, so a later job animates again", async () => {
    // Fill the cap, then let them all settle; a fresh job should be under the
    // cap again (instant:false) — slots are released on settle.
    const jobs = []
    for (let i = 0; i < 4; i++) jobs.push(enqueue(() => Promise.resolve()))
    await Promise.all(jobs)

    let opt
    await enqueue((o) => { opt = o; return Promise.resolve() })
    expect(opt.instant).toBe(false)
  })
})
