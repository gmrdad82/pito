// pito/typing.js
//
// Shared per-character typing constants used by both:
//   • typewriter_controller.js  (assistant response reveal)
//   • type_fx_controller.js     (chatbox per-char phase-in)
//
// Keeping them in one place ensures the reveal cadence matches
// the chatbox animation so the UI feels consistent.

export const TICK_MS    = 12   // ms per tick
export const CHARS_TICK = 2    // characters revealed per tick (fast)
