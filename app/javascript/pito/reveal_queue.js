// pito/reveal_queue.js
//
// Singleton FIFO queue for typewriter reveal jobs.
//
// Usage:
//   import { enqueue } from "pito/reveal_queue"
//   enqueue(revealFn)  // revealFn(opts) → Promise
//
// Each revealFn receives { instant: Boolean }.  When instant is true the
// function must set full text immediately and resolve without animation.
//
// Backpressure: when more than CAP jobs are already waiting, new jobs are
// called with { instant: true } so the UI never lags behind reality.

const CAP = 3  // max waiting jobs before instant-mode kicks in

let tail    = Promise.resolve()  // end of the promise chain
let waiting = 0                  // jobs enqueued but not yet started

export function enqueue(revealFn) {
  const instant = waiting > CAP
  waiting++

  const job = tail.then(() => {
    waiting = Math.max(0, waiting - 1)
    return revealFn({ instant })
  })

  // Never let one failed/slow reveal poison the chain — a rejected `tail` would
  // skip the `.then` of every later job, so messages would clear but never type
  // until a refresh. Keep the chain on a resolved branch.
  tail = job.catch((err) => {
    console.warn("[pito reveal] job failed:", err)
  })

  return job
}
