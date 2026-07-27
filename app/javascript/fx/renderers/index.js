// The enforcer renderer registry (2.1.0 P5): name → renderer module. The
// context engine treats an unregistered effect as non-viable and lets the
// sky answer, so this file IS the rollout switch — and, since the 5.0.0
// cull, the kill switch too.
//
// TWO MOODS MOUNT HERE. `sky` is the third shipped effect but is NOT a
// renderer: it lives at fx/sky.js and is painted by the fx controller's own
// resting pass, so it is deliberately absent from this map — which is how
// `{ effect: sky }` in a context pool resolves to "the sky answers"
// (fx/engine.js viable() → no renderer → non-viable → empty pool → null).
//
// THE 5.0.0 CULL (owner ruling 2026-07-26): duotone, lens, glow, trails,
// aurora, globs and cover_wall were deleted from this directory together
// with their config/pito/fx.yml entries. cover_wall was the only CSS-engine
// renderer, so the DOM-instance path it needed (an `element` instead of a
// `canvas`, mounted into the controller's wall layer) now has no user —
// pito--fx_controller.js still implements it, unexercised, and the contract
// below is written for the canvas renderers that actually ship.
//
// THE RENDERER CONTRACT (every module in this directory):
//
//   export default {
//     create({ width, height, dpr, knobs, covers }) → instance | null
//   }
//
//   instance = {
//     canvas,                    // its OWN offscreen canvas (the compositor
//                                // drawImage()s it onto the visible canvas
//                                // at the crossfade alpha — F4's one visible
//                                // canvas, passes composited)
//     frame(dtMs, phase, attractor), // paint one frame; attractor =
//                                // {x, y, vx, vy, impulse} in 0..1 viewport
//                                // space — the butterfly (P6). NEVER read
//                                // the pointer directly (F7).
//     resize(width, height),
//     ready() → bool,            // false while covers/textures load
//     destroy(),                  // release GL context via
//                                // WEBGL_lose_context where applicable
//   }
//
//   Rules: self-contained (no imports, no DOM queries outside the own
//   canvas, no listeners); WebGL2 only via the own canvas's context;
//   return null from create() when the environment can't run it.
import plasma from "fx/renderers/plasma"
import water from "fx/renderers/water"

export default { plasma, water }
