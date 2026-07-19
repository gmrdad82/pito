// plasma — domain-warped 4-octave fbm noise (was 5), dark → pito-blue
// (#5170ff) → purple palette. Ported verbatim (GLSL only) from pitomd's
// PLASMA_FRAG + plasma() factory (src/scripts/fx-webgl.js lines 898-1024).
// Re-synced 2026-07-19 to pitomd's fidelity tuning: OCTAVES 5→4, and the old
// second fbm-pair ("r", a re-warp reusing warped*1.6 ± 4.0) folded into
// reusing the first warp field q — 3 fbm calls/pixel now, was 5. Both ports
// share pitomd's ≤12 fbm-octave/pixel budget (3 calls * OCTAVES(4) = 12,
// was 5 calls * 5 octaves = 25 — a ~52% cut). The JS wiring is rebuilt here
// to the enforcer renderer contract (see ./index.js):
//
//   - own offscreen canvas (created here, never queried from the DOM)
//   - frame(dtMs, phase, attractor) replaces pitomd's raw cursor/mouse feed —
//     attractor.{x,y} (0..1, viewport-relative, y-down/top-left origin) are
//     mapped to a gl_FragCoord-space pixel (GL's frag coord is bottom-up, so
//     y is flipped); attractor.impulse (0..1, decaying) mildly strengthens
//     the cursor-pull term instead of pitomd's constant pull.
//   - knobs.speed (default 1.0) scales the time uniform.
//
// Self-contained per the contract: no imports, no DOM queries outside its
// own canvas, no listeners, no pointer access.

const VERT = `#version 300 es
in vec2 p;
void main() {
  gl_Position = vec4(p, 0.0, 1.0);
}`;

const FRAG = `#version 300 es
precision highp float;

uniform vec2 u_res;
uniform float u_time;
uniform vec2 u_focus; // the leader butterfly, never the pointer (renamed from the port's mouse uniform)
uniform float u_pull;

out vec4 outColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Octave count per fbm call — was 5. Perf budget (owner: halve plasma's
// per-pixel cost): main() below issues 3 fbm calls/pixel (was 5 — the old
// "r" re-warp pair collapsed into reusing q, see below), so
// 3 calls * OCTAVES(4) = 12 octave-units/pixel (was 5 calls * 5 octaves = 25).
const int OCTAVES = 4;

float fbm(vec2 p) {
  float sum = 0.0;
  float amp = 0.5;
  for (int i = 0; i < OCTAVES; i++) {
    sum += amp * noise(p);
    p *= 2.02;
    amp *= 0.5;
  }
  return sum;
}

void main() {
  float shortSide = min(u_res.x, u_res.y);
  vec2 uv = (gl_FragCoord.xy - 0.5 * u_res) / shortSide;
  vec2 focusUv = (u_focus - 0.5 * u_res) / shortSide;

  // domain warp: warp the sample coordinate by a second fbm field
  vec2 q = vec2(
    fbm(uv + u_time * 0.05),
    fbm(uv + vec2(1.7, 9.2) + u_time * 0.04)
  );
  vec2 warped = uv + q * 0.6;

  // pull the warp toward the attractor with a soft falloff; u_pull (the
  // attractor's decaying impulse) mildly strengthens the pull term.
  float dist = length(uv - focusUv);
  float pull = exp(-dist * 2.2) * (1.0 + u_pull * 0.5);
  warped = mix(warped, focusUv, pull * 0.5);

  // re-warp: reuse q instead of a second fbm-pair "r" field (previously 2
  // more fbm calls: r.x/r.y from warped, phase +/-4.0, at 0.03 * u_time) —
  // folds the same warp field back in, still reads as a domain-warped
  // re-warp for 2 fewer fbm calls per pixel.
  float n = fbm(warped * 1.2 + q * 1.4);

  vec3 dark = vec3(0.02, 0.02, 0.04);
  vec3 blue = vec3(0.318, 0.439, 1.0);
  vec3 purple = vec3(0.541, 0.424, 1.0);

  vec3 col = mix(dark, blue, smoothstep(0.15, 0.65, n));
  col = mix(col, purple, smoothstep(0.55, 0.95, n));

  float core = smoothstep(0.82, 1.05, n) + pull * 0.35;
  col += core * vec3(0.75, 0.8, 1.0) * 0.6;

  outColor = vec4(col, 1.0);
}`;

function compileShader(gl, type, src) {
  const sh = gl.createShader(type);
  gl.shaderSource(sh, src);
  gl.compileShader(sh);
  if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(sh) || "shader compile failed";
    gl.deleteShader(sh);
    throw new Error(log);
  }
  return sh;
}

function linkProgram(gl, vertSrc, fragSrc) {
  const prog = gl.createProgram();
  gl.attachShader(prog, compileShader(gl, gl.VERTEX_SHADER, vertSrc));
  gl.attachShader(prog, compileShader(gl, gl.FRAGMENT_SHADER, fragSrc));
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    const log = gl.getProgramInfoLog(prog) || "program link failed";
    gl.deleteProgram(prog);
    throw new Error(log);
  }
  return prog;
}

// one fullscreen-triangle buffer bound to the program's "p" attribute.
function bindFullscreenTriangle(gl, prog) {
  const vao = gl.createVertexArray();
  gl.bindVertexArray(vao);
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 3, -1, -1, 3]),
    gl.STATIC_DRAW,
  );
  const loc = gl.getAttribLocation(prog, "p");
  gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  return vao;
}

function create({ width, height, dpr, knobs } = {}) {
  const canvas = document.createElement("canvas");
  const gl = canvas.getContext("webgl2");
  if (!gl) return null;

  const scale = dpr || 1;
  const speed = (knobs && typeof knobs.speed === "number") ? knobs.speed : 1.0;

  canvas.width = Math.max(1, Math.round((width || 1) * scale));
  canvas.height = Math.max(1, Math.round((height || 1) * scale));

  let prog;
  let vao;
  try {
    prog = linkProgram(gl, VERT, FRAG);
    vao = bindFullscreenTriangle(gl, prog);
  } catch {
    return null;
  }

  const u = {
    u_res: gl.getUniformLocation(prog, "u_res"),
    u_time: gl.getUniformLocation(prog, "u_time"),
    u_focus: gl.getUniformLocation(prog, "u_focus"),
    u_pull: gl.getUniformLocation(prog, "u_pull"),
  };

  gl.viewport(0, 0, canvas.width, canvas.height);

  let elapsed = 0;
  let destroyed = false;

  function frame(dtMs, phase, attractor) {
    if (destroyed) return;
    elapsed += ((dtMs || 0) / 1000) * speed;

    const ax = attractor ? attractor.x : 0.5;
    const ay = attractor ? attractor.y : 0.5;
    const impulse = attractor ? attractor.impulse || 0 : 0;

    gl.useProgram(prog);
    gl.bindVertexArray(vao);
    gl.uniform2f(u.u_res, canvas.width, canvas.height);
    gl.uniform1f(u.u_time, elapsed);
    // gl_FragCoord is bottom-up; attractor.y is top-left-origin, so flip it.
    gl.uniform2f(u.u_focus, ax * canvas.width, (1 - ay) * canvas.height);
    gl.uniform1f(u.u_pull, impulse);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  function resize(w, h) {
    canvas.width = Math.max(1, Math.round((w || 1) * scale));
    canvas.height = Math.max(1, Math.round((h || 1) * scale));
    gl.viewport(0, 0, canvas.width, canvas.height);
  }

  function ready() {
    return true;
  }

  function destroy() {
    destroyed = true;
    gl.getExtension("WEBGL_lose_context")?.loseContext();
  }

  return { canvas, frame, resize, ready, destroy };
}

export default { create };
