import { describe, it, expect } from "vitest"
import { readFileSync } from "fs"
import { fileURLToPath } from "url"
import { dirname, resolve } from "path"

// plasma's FRAG is a private module-scope const (no pure seam: create()
// wants a real WebGL2 context, which jsdom doesn't provide, and nothing in
// the fragment shader is exposed as a callable JS function) — so this pins
// the octave/call-site budget the same way the pitomd↔pito fidelity diff
// does: by regexing the raw shader source string, not by executing it. See
// the header comment on fx/renderers/plasma.js for the 2026-07-19 re-sync
// this guards against silently drifting back open.
const __dirname = dirname(fileURLToPath(import.meta.url))
const SRC = readFileSync(
  resolve(__dirname, "../../../app/javascript/fx/renderers/plasma.js"),
  "utf8",
)
const FRAG = SRC.match(/const FRAG = `([^`]+)`/)?.[1]
const MAIN_BODY = FRAG?.match(/void main\(\) \{([\s\S]+)\}$/)?.[1]

describe("plasma's shader budget (text-pin — no WebGL under jsdom)", () => {
  it("found FRAG and main() to pin", () => {
    expect(FRAG).toBeTruthy()
    expect(MAIN_BODY).toBeTruthy()
  })

  it("caps the fbm octave count at OCTAVES(4) — was 5, pitomd's 2026-07-19 fidelity tuning", () => {
    const octaves = FRAG.match(/const int OCTAVES = (\d+);/)?.[1]
    expect(Number(octaves)).toBe(4)
  })

  it("issues 3 fbm call-sites/pixel in main() — was 5 (the \"r\" re-warp pair folded into reusing q)", () => {
    const callSites = MAIN_BODY.match(/\bfbm\(/g) || []
    expect(callSites.length).toBe(3)
  })

  it("keeps the shared ≤12 fbm-octave/pixel budget (calls * OCTAVES)", () => {
    const octaves = Number(FRAG.match(/const int OCTAVES = (\d+);/)?.[1])
    const calls = (MAIN_BODY.match(/\bfbm\(/g) || []).length
    expect(calls * octaves).toBeLessThanOrEqual(12)
  })
})
