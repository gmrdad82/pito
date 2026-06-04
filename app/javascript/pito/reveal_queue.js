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

  tail = tail.then(() => {
    waiting = Math.max(0, waiting - 1)
    return revealFn({ instant })
  })

  return tail
}
