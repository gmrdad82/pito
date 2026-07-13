// duotone — the owner's name for the locked dual-tone halftone dot grid,
// rendering a game cover. Ported from pitomd's fx-webgl.js (HALFTONE_FRAG +
// halftone(), ~lines 1130-1250) onto this registry's per-module-canvas
// contract (see renderers/index.js). Dots sharpen and brighten near the
// attractor's focus point; the base tone sweeps purple -> pito-blue across
// the diagonal (owner-tuned dual-tone, ported verbatim).
//
// Self-contained: no imports, no listeners, no DOM access beyond this
// module's own canvas, no pointer reads — the attractor argument of frame()
// replaces the cursor entirely (F7).

const VERT = `#version 300 es
in vec2 p;
void main() {
  gl_Position = vec4(p, 0.0, 1.0);
}`

const FRAG = `#version 300 es
precision highp float;

uniform sampler2D u_image;
uniform vec2 u_res;
uniform vec2 u_imgSize;
uniform vec2 u_focus[3];
uniform float u_focusR[3];
uniform int u_count;
uniform float u_time;
uniform float u_cellMin;
uniform float u_cellMax;

out vec4 outColor;

void main() {
  // Up to three focus circles (owner 2026-07-13), each its own radius; a
  // fragment answers to its NEAREST-strongest focus.
  float t = 0.0;
  for (int i = 0; i < 3; i++) {
    if (i >= u_count) break;
    float dist = distance(gl_FragCoord.xy, u_focus[i]);
    t = max(t, 1.0 - smoothstep(0.0, u_focusR[i], dist));
  }
  float cellSize = mix(u_cellMax, u_cellMin, t);

  vec2 cell = floor(gl_FragCoord.xy / cellSize);
  vec2 cellCenter = (cell + 0.5) * cellSize;

  float scale = max(u_res.x / u_imgSize.x, u_res.y / u_imgSize.y);
  vec2 dispSize = u_imgSize * scale;
  vec2 offset = (u_res - dispSize) * 0.5;
  vec2 uv = clamp((cellCenter - offset) / dispSize, 0.0, 1.0);

  vec3 texel = texture(u_image, uv).rgb;
  float lum = dot(texel, vec3(0.299, 0.587, 0.114));

  vec2 local = (gl_FragCoord.xy - cell * cellSize) / cellSize - 0.5;
  float r = length(local);
  float dotRadius = clamp(lum, 0.0, 1.0) * 0.44 + 0.03 * t;
  float mask = 1.0 - smoothstep(dotRadius - 0.08, dotRadius + 0.08, r);

  vec3 bg = vec3(0.039, 0.039, 0.071);
  /* dual-tone (owner-tuned): purple -> pito-blue across the diagonal instead
     of flat blue, still brightening toward the focus point */
  float g = clamp(
    (gl_FragCoord.x / u_res.x + gl_FragCoord.y / u_res.y) * 0.5, 0.0, 1.0);
  vec3 purple = vec3(0.545, 0.361, 0.965);
  vec3 blue = vec3(0.318, 0.439, 1.0);
  vec3 tone = mix(purple, blue, g) * mix(0.75, 1.2, t);
  vec3 col = mix(bg, tone, mask);

  outColor = vec4(col, 1.0);
}`

// device-pixel safety ceiling, ported from fx-webgl.js's CANVAS_MAX —
// insurance against ever sizing the canvas past the GPU's max texture size.
// Raised to 4096 (the WebGL2 floor) so the duotone's 2x supersample
// (owner: "improve the effect resolution") survives on wide desktops.
const CANVAS_MAX = 4096

function compileShader(gl, type, src) {
  const sh = gl.createShader(type)
  gl.shaderSource(sh, src)
  gl.compileShader(sh)
  if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
    gl.deleteShader(sh)
    return null
  }
  return sh
}

function linkProgram(gl, vertSrc, fragSrc) {
  const vert = compileShader(gl, gl.VERTEX_SHADER, vertSrc)
  const frag = compileShader(gl, gl.FRAGMENT_SHADER, fragSrc)
  if (!vert || !frag) return null
  const prog = gl.createProgram()
  gl.attachShader(prog, vert)
  gl.attachShader(prog, frag)
  gl.linkProgram(prog)
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    gl.deleteProgram(prog)
    return null
  }
  return prog
}

// one fullscreen-triangle buffer, its "p" attribute bound on the program —
// mirrors fx-webgl.js's bindFullscreenTriangle.
function bindFullscreenTriangle(gl, prog) {
  const vao = gl.createVertexArray()
  gl.bindVertexArray(vao)
  const buf = gl.createBuffer()
  gl.bindBuffer(gl.ARRAY_BUFFER, buf)
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 3, -1, -1, 3]),
    gl.STATIC_DRAW,
  )
  const loc = gl.getAttribLocation(prog, "p")
  gl.enableVertexAttribArray(loc)
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0)
  return vao
}

// flip-Y + linear + clamp upload, ported verbatim from fx-webgl.js's
// uploadCoverTexture.
function uploadCoverTexture(gl, img) {
  const tex = gl.createTexture()
  gl.bindTexture(gl.TEXTURE_2D, tex)
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true)
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, img)
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false)
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
  return tex
}

function sizeCanvas(canvas, width, height, dpr) {
  canvas.width = Math.max(1, Math.min(CANVAS_MAX, Math.round(width * dpr)))
  canvas.height = Math.max(1, Math.min(CANVAS_MAX, Math.round(height * dpr)))
}

export default {
  create({ width, height, dpr, knobs, covers }) {
    if (!covers || covers.length === 0) return null

    const canvas = document.createElement("canvas")
    const gl = canvas.getContext("webgl2")
    if (!gl) return null

    const prog = linkProgram(gl, VERT, FRAG)
    if (!prog) return null
    const vao = bindFullscreenTriangle(gl, prog)

    const u = {
      image: gl.getUniformLocation(prog, "u_image"),
      res: gl.getUniformLocation(prog, "u_res"),
      imgSize: gl.getUniformLocation(prog, "u_imgSize"),
      focus: gl.getUniformLocation(prog, "u_focus"),
      focusR: gl.getUniformLocation(prog, "u_focusR"),
      count: gl.getUniformLocation(prog, "u_count"),
      time: gl.getUniformLocation(prog, "u_time"),
      cellMin: gl.getUniformLocation(prog, "u_cellMin"),
      cellMax: gl.getUniformLocation(prog, "u_cellMax"),
    }

    const k = knobs || {}
    const cellMin = k.cell_min ?? 5.0
    const cellMax = k.cell_max ?? 15.0

    // knobs.dpr SUPERSAMPLES past the engine's global dpr cap — the shader
    // is one texture sample per fragment, cheap enough to render at 2x and
    // let the compositor's downscale anti-alias the dot edges (owner:
    // "improve the effect resolution"). Cell knobs are in CANVAS pixels, so
    // visual dot size = knob / dpr.
    const currentDpr = k.dpr ?? dpr ?? 1
    sizeCanvas(canvas, width, height, currentDpr)
    gl.viewport(0, 0, canvas.width, canvas.height)

    let destroyed = false
    let loaded = false
    let texture = null
    let imgSize = [1, 1]

    // covers[0] only — same-origin, so no crossOrigin dance needed.
    const img = new Image()
    img.addEventListener(
      "load",
      () => {
        if (destroyed) return
        texture = uploadCoverTexture(gl, img)
        imgSize = [img.naturalWidth || 1, img.naturalHeight || 1]
        loaded = true
      },
      { once: true },
    )
    img.src = covers[0]

    // Focus count scales with the viewport (owner: 3 on desktop, 1 on a
    // phone), sizes tiered so no two circles match.
    const focusCount = Math.max(1, Math.min(3, Math.round(Math.min(width, height) / 400)))
    const SIZE_TIERS = [1.0, 0.72, 0.52]
    const focusBase = Math.max(180, Math.min(width, height) * 0.32)

    function frame(dtMs, phase, attractor) {
      if (destroyed || !loaded) return

      // Each circle follows a flock member (0..1 top-left space; gl_FragCoord
      // is y-up, so flip y the same way the reference's localMouseUv did).
      const flock = (attractor && attractor.flock && attractor.flock.length
        ? attractor.flock
        : [attractor || { x: 0.5, y: 0.5 }]).slice(0, focusCount)
      const focus = new Float32Array(6)
      const focusR = new Float32Array(3)
      flock.forEach((body, i) => {
        focus[i * 2] = body.x * canvas.width
        focus[i * 2 + 1] = (1 - body.y) * canvas.height
        focusR[i] = focusBase * SIZE_TIERS[i]
      })

      gl.useProgram(prog)
      gl.bindVertexArray(vao)
      gl.uniform2f(u.res, canvas.width, canvas.height)
      gl.uniform1f(u.time, phase || 0)
      gl.uniform2fv(u.focus, focus)
      gl.uniform1fv(u.focusR, focusR)
      gl.uniform1i(u.count, flock.length)
      gl.uniform2f(u.imgSize, imgSize[0], imgSize[1])
      gl.uniform1f(u.cellMin, cellMin)
      gl.uniform1f(u.cellMax, cellMax)
      gl.activeTexture(gl.TEXTURE0)
      gl.bindTexture(gl.TEXTURE_2D, texture)
      gl.uniform1i(u.image, 0)
      gl.drawArrays(gl.TRIANGLES, 0, 3)
    }

    function resize(w, h) {
      sizeCanvas(canvas, w, h, currentDpr)
      gl.viewport(0, 0, canvas.width, canvas.height)
    }

    function ready() {
      return loaded && !destroyed
    }

    function destroy() {
      destroyed = true
      if (texture) gl.deleteTexture(texture)
      const ext = gl.getExtension("WEBGL_lose_context")
      if (ext) ext.loseContext()
    }

    return { canvas, frame, resize, ready, destroy }
  },
}
