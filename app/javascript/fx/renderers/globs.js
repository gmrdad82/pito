// globs — gooey metaball field: driven blobs riding the flock (no cursor)
// plus six ambient time-driven blobs on lissajous orbits, dark -> pito-blue
// -> purple palette. Ported verbatim (GLSL field/threshold/coloring
// unchanged) from pitomd's METABALLS_VERT/FRAG + metaballs() factory
// (src/scripts/fx-webgl.js lines ~1020-1120), by way of the approved gallery
// adaptation (tmp/fx/globs.html — owner-locked "globs perfect" 2026-07-13)
// which already swapped the single cursor-pinned blob for three JS-driven
// walker uniforms. The JS wiring is rebuilt here to the enforcer renderer
// contract (see ./index.js):
//
//   - own offscreen canvas (created here, never queried from the DOM)
//   - frame(dtMs, phase, attractor) replaces pitomd's raw cursor feed AND the
//     gallery's autonomous walkerPx() simulation: attractor.flock
//     ([{x,y} in 0..1], viewport-relative, top-left origin) is the
//     driven-blob source — up to MAX_WALKERS (6, the flock ceiling per
//     fx.yml's engine.butterflies) positions upload to the u_walkers array
//     uniform, u_walkerCount tells the shader how many are live (same
//     count-uniform + break-in-loop pattern as lens.js's u_focus/u_count).
//     Only x/y are used — no cursor, no impulse-driven sizing. gl_FragCoord
//     is bottom-up, so y flips the same way lens.js's focus upload does.
//   - the six ambient blobs are untouched from the source — pure u_time
//     lissajous drift, no attractor input at all.
//   - tint_source: theme (fx.yml) — mirrors plasma.js: the dark/blue/purple
//     palette is baked into the GLSL as constants (pito's own theme, not a
//     cover sample), no CSS/DOM read.
//   - knobs.blob_scale (default 1.0) scales EVERY blob's visual radius
//     uniformly (driven and ambient alike) by shrinking the sampled distance
//     before the field falloff, fed as the u_blobScale uniform.
//
// Self-contained per the contract: no imports, no DOM queries outside its
// own canvas, no listeners, no pointer access.

const MAX_WALKERS = 6;

const VERT = `#version 300 es
in vec2 p;
void main() {
  gl_Position = vec4(p, 0.0, 1.0);
}`;

const FRAG = `#version 300 es
precision highp float;

uniform vec2 u_res;
uniform float u_time;
uniform vec2 u_walkers[${MAX_WALKERS}];
uniform int u_walkerCount;
uniform float u_blobScale;

out vec4 outColor;

void main() {
  float shortSide = min(u_res.x, u_res.y);
  vec2 uv = (gl_FragCoord.xy - 0.5 * u_res) / shortSide;

  float field = 0.0;

  // driven blobs: up to MAX_WALKERS, one per live flock member (no cursor).
  for (int i = 0; i < ${MAX_WALKERS}; i++) {
    if (i >= u_walkerCount) break;
    vec2 w = (u_walkers[i] - 0.5 * u_res) / shortSide;
    vec2 d = (uv - w) / u_blobScale;
    field += 0.020 / (dot(d, d) + 0.0009);
  }

  // six drifting blobs, each on its own lissajous-ish orbit (ambient,
  // time-driven only — unchanged from the source).
  for (int i = 0; i < 6; i++) {
    float fi = float(i);
    float speed = 0.35 + fi * 0.08;
    float radius = 0.5 + fi * 0.15;
    vec2 pos = vec2(
      cos(u_time * speed + fi * 2.1) * radius * 0.55,
      sin(u_time * speed * 0.8 + fi * 1.7) * radius * 0.4
    );
    vec2 d = (uv - pos) / u_blobScale;
    float strength = 0.013 + 0.004 * sin(fi * 1.3);
    field += strength / (dot(d, d) + 0.0012);
  }

  float edge = smoothstep(0.9, 1.15, field);
  float rim = smoothstep(0.7, 0.95, field) - edge;

  vec3 bg = vec3(0.039, 0.039, 0.071);
  vec3 blue = vec3(0.318, 0.439, 1.0);
  vec3 purple = vec3(0.541, 0.424, 1.0);

  vec3 col = bg;
  col = mix(col, blue, edge);
  col += max(rim, 0.0) * purple * 0.9;
  col += edge * blue * (0.15 + 0.1 * sin(u_time * 2.0 + field * 3.0));

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
  const blobScale =
    knobs && typeof knobs.blob_scale === "number" ? knobs.blob_scale : 1.0;

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
    u_walkers: gl.getUniformLocation(prog, "u_walkers"),
    u_walkerCount: gl.getUniformLocation(prog, "u_walkerCount"),
    u_blobScale: gl.getUniformLocation(prog, "u_blobScale"),
  };

  gl.viewport(0, 0, canvas.width, canvas.height);

  let elapsed = 0;
  let destroyed = false;
  const walkers = new Float32Array(MAX_WALKERS * 2);

  function frame(dtMs, _phase, attractor) {
    if (destroyed) return;
    elapsed += (dtMs || 0) / 1000;

    // Driven blobs ride the flock (owner 2026-07-13: no cursor anywhere) —
    // one per live member, capped at MAX_WALKERS; falls back to a single
    // centered blob when no flock is present.
    const flock = (
      attractor && attractor.flock && attractor.flock.length
        ? attractor.flock
        : [attractor || { x: 0.5, y: 0.5 }]
    ).slice(0, MAX_WALKERS);
    flock.forEach((body, i) => {
      // gl_FragCoord is bottom-up; body.y is top-left-origin, so flip it.
      walkers[i * 2] = body.x * canvas.width;
      walkers[i * 2 + 1] = (1 - body.y) * canvas.height;
    });

    gl.useProgram(prog);
    gl.bindVertexArray(vao);
    gl.uniform2f(u.u_res, canvas.width, canvas.height);
    gl.uniform1f(u.u_time, elapsed);
    gl.uniform2fv(u.u_walkers, walkers);
    gl.uniform1i(u.u_walkerCount, flock.length);
    gl.uniform1f(u.u_blobScale, blobScale);
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
