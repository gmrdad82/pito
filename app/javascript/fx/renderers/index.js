// The enforcer renderer registry (2.1.0 P5): name → renderer module. The
// context engine treats an unregistered effect as non-viable and lets the
// sky answer, so this file growing IS the rollout switch.
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
//
//   CSS-ENGINE VARIANT (cover_wall): instead of `canvas`, the instance
//   exposes `element` — a self-built DOM node the compositor mounts into
//   the fx layer and drives via style.opacity = crossfade alpha. frame()
//   updates the element's custom properties (butterfly drift); destroy()
//   removes it.
import plasma from "fx/renderers/plasma"
import glow from "fx/renderers/glow"
import globs from "fx/renderers/globs"
import aurora from "fx/renderers/aurora"
import trails from "fx/renderers/trails"
import duotone from "fx/renderers/duotone"
import water from "fx/renderers/water"
import lens from "fx/renderers/lens"
import cover_wall from "fx/renderers/cover_wall"

export default { plasma, glow, globs, aurora, trails, duotone, water, lens, cover_wall }
