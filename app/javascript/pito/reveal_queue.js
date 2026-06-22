// pito/reveal_queue.js
//
// Concurrency limiter for typewriter reveal jobs.
//
// Usage:
//   import { enqueue } from "pito/reveal_queue"
//   enqueue(revealFn)  // revealFn(opts) → Promise
//
// Each revealFn receives { instant: Boolean }.  When instant is true the
// function must set full text immediately and resolve without animation.
//
// Concurrency (NOT a FIFO):
//   Every job starts IMMEDIATELY and runs CONCURRENTLY — a new message's reveal
//   never waits on a previous message's card still animating. This is the K3
//   contract: each message (and its segments) types in independently as it
//   arrives, instead of a global FIFO blocking everything behind one slow card.
//
// Backpressure: when MAX_CONCURRENT reveals are already animating, the next job
// is called with { instant: true } so a large burst never leaves the UI lagging
// far behind reality (it snaps the overflow in instantly rather than queueing a
// long tail of sequential animations).

const MAX_CONCURRENT = 4  // reveals allowed to animate at once before instant-mode

let active = 0  // jobs currently in flight (enqueued, not yet settled)

function release() {
  active = Math.max(0, active - 1)
}

export function enqueue(revealFn) {
  const instant = active >= MAX_CONCURRENT
  active++

  // Start in a fresh microtask so enqueue() stays synchronous, but do NOT chain
  // on any other job — every reveal runs concurrently.
  const job = Promise.resolve().then(() => revealFn({ instant }))

  // Always release the slot when the job settles, success or failure. Attaching
  // a rejection handler here also prevents an unhandled-rejection warning while
  // STILL letting the returned `job` reject for the caller (error isolation: one
  // failed reveal never affects another, since jobs are independent).
  job.then(release, (err) => {
    release()
    console.warn("[pito reveal] job failed:", err)
  })

  return job
}

// Test-only: reset the in-flight counter so the module-global backpressure state
// can't leak between isolated test cases (a prior test's unsettled job must not
// push a later test's reveal into instant mode). Never called in production.
export function __resetForTest() {
  active = 0
}
