// lens.js — the lens mood: a chromatic-refraction magnifier over the game
// cover with a rotating neon rim (purple -> pito-blue -> pink). Ported from
// pitomd's fx-webgl.js lens() (LENS_VERT/LENS_FRAG ~L1254-1333, factory
// ~L1335-1406, uploadCoverTexture ~L169-193, GL boilerplate ~L64-132),
// self-contained per THE RENDERER CONTRACT in ./index.js: no imports, no DOM
// queries outside this module's own canvas, no listeners, WebGL2-only, null
// when the environment can't run it.
//
// Adaptations from the pitomd source (mirrors water.js/plasma.js's already-
// ported conventions):
//   - covers[0] (not a CSS custom property parse) loads via new Image();
//     ready()/frame() stay gated until the texture lands.
//   - frame(dtMs, _phase, attractor) replaces the raw rAF-timestamp + pointer
//     feed: attractor.{x,y} (0..1, viewport-relative, top-left origin) map to
//     a gl_FragCoord-space pixel — GL's frag coord is bottom-up, so y flips.
//     attractor.impulse (0..1, decaying) briefly widens the lens instead of
//     the reference's fixed 200px radius.
//   - knobs.radius (default 180px) replaces the hardcoded lensRadius literal;
//     fed to the shader as a uniform instead of a GLSL constant.

const LENS_VERT = `#version 300 es
in vec2 p;
void main() {
  gl_Position = vec4(p, 0.0, 1.0);
}`;

const LENS_FRAG = `#version 300 es
precision highp float;

uniform sampler2D u_image;
uniform vec2 u_res;
uniform vec2 u_imgSize;
uniform vec2 u_focus[3];
uniform float u_radius[3];
uniform int u_count;
uniform float u_time;

out vec4 outColor;

vec2 coverUv(vec2 px) {
  float scale = max(u_res.x / u_imgSize.x, u_res.y / u_imgSize.y);
  vec2 dispSize = u_imgSize * scale;
  vec2 offset = (u_res - dispSize) * 0.5;
  return (px - offset) / dispSize;
}

void main() {
  vec2 uv = clamp(coverUv(gl_FragCoord.xy), 0.0, 1.0);
  vec3 baseColor = texture(u_image, uv).rgb;
  float lum = dot(baseColor, vec3(0.299, 0.587, 0.114));
  vec3 dimmed = mix(vec3(lum), baseColor, 0.3) * 0.4;

  vec3 col = dimmed;

  // Up to three lenses (owner 2026-07-13: several big reveal circles at
  // different sizes; the separation lives in the flock, not the shader).
  for (int i = 0; i < 3; i++) {
    if (i >= u_count) break;
    float lensRadius = u_radius[i];
    vec2 toFocus = gl_FragCoord.xy - u_focus[i];
    float dist = length(toFocus);
    vec2 dir = toFocus / max(dist, 0.0001);
    float inLens = 1.0 - smoothstep(lensRadius * 0.82, lensRadius, dist);

    float mag = 0.55;
    vec2 magnifiedPx = u_focus[i] + toFocus * mag;
    float curve = smoothstep(0.0, lensRadius, dist);
    vec2 refractPx = dir * curve * 10.0;
    vec2 lensUv = clamp(coverUv(magnifiedPx + refractPx), 0.0, 1.0);

    float shortSide = min(u_res.x, u_res.y);
    float aberration = (dist / lensRadius) * 7.0;
    vec2 aberrUv = dir * aberration / shortSide;

    float rC = texture(u_image, clamp(lensUv + aberrUv, 0.0, 1.0)).r;
    float gC = texture(u_image, lensUv).g;
    float bC = texture(u_image, clamp(lensUv - aberrUv, 0.0, 1.0)).b;
    vec3 lensColor = vec3(rC, gC, bC);

    col = mix(col, lensColor, inLens);

    // Rim profile in PIXEL units (thin at any radius): a bright edge at the
    // boundary, anti-aliased ~1px outward, decaying smoothly to zero ~2px
    // inward.
    float edgeDist = dist - lensRadius;
    float rimOuter = 1.0 - smoothstep(0.0, 1.0, edgeDist);
    float rimInner = smoothstep(-2.0, 0.0, edgeDist);
    float rim = rimInner * rimOuter;

    // Neon gradient around the circumference: cyclic cosine-lobe blend of
    // purple -> pito-blue -> pink (three lobes 120deg apart wrap seamlessly
    // at +/-pi); u_time slowly rotates it at ~0.3 rad/s.
    float rimAngle = atan(toFocus.y, toFocus.x) + u_time * 0.3;
    vec3 rimPurple = vec3(0.545, 0.361, 0.965);
    vec3 rimBlue = vec3(0.318, 0.439, 1.0);
    vec3 rimPink = vec3(1.0, 0.431, 0.780);
    float wPurple = 0.5 + 0.5 * cos(rimAngle);
    float wBlue = 0.5 + 0.5 * cos(rimAngle - 2.0943951);
    float wPink = 0.5 + 0.5 * cos(rimAngle - 4.1887902);
    vec3 neon =
        (rimPurple * wPurple + rimBlue * wBlue + rimPink * wPink) /
        (wPurple + wBlue + wPink);

    col += rim * neon;
  }

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

// one fullscreen-triangle buffer, its "p" attribute bound on every program
// that shares it.
function bindFullscreenTriangle(gl, programs) {
  const vao = gl.createVertexArray();
  gl.bindVertexArray(vao);
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 3, -1, -1, 3]),
    gl.STATIC_DRAW,
  );
  for (const prog of programs) {
    const loc = gl.getAttribLocation(prog, "p");
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  }
  return vao;
}

function uploadCoverTexture(gl, img) {
  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, img);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  return tex;
}

const DEFAULT_RADIUS = 180.0; // px; knobs.radius overrides — the lens circle's base size
const IMPULSE_WIDEN = 0.3; // attractor.impulse (0..1) widens the lens up to +30% at its peak

function create({ width, height, dpr, knobs, covers }) {
  if (!covers || covers.length === 0) return null;

  const canvas = document.createElement("canvas");
  const gl = canvas.getContext("webgl2");
  if (!gl) return null;

  const radiusKnob =
    knobs && typeof knobs.radius === "number" ? knobs.radius : DEFAULT_RADIUS;

  let prog, vao;
  try {
    prog = linkProgram(gl, LENS_VERT, LENS_FRAG);
    vao = bindFullscreenTriangle(gl, [prog]);
  } catch (_e) {
    return null;
  }

  const u = {
    image: gl.getUniformLocation(prog, "u_image"),
    res: gl.getUniformLocation(prog, "u_res"),
    imgSize: gl.getUniformLocation(prog, "u_imgSize"),
    focus: gl.getUniformLocation(prog, "u_focus"),
    count: gl.getUniformLocation(prog, "u_count"),
    time: gl.getUniformLocation(prog, "u_time"),
    radius: gl.getUniformLocation(prog, "u_radius"),
  };

  // Lens COUNT scales with the viewport (owner: "based on view port, I want
  // more" — 3 on a desktop, 1 on a phone), each a different size.
  const lensCount = Math.max(1, Math.min(3, Math.round(Math.min(width, height) / 400)));
  const SIZE_TIERS = [1.0, 0.72, 0.52];

  const pixelRatio = dpr || 1;
  canvas.width = Math.max(1, Math.round(width * pixelRatio));
  canvas.height = Math.max(1, Math.round(height * pixelRatio));
  gl.viewport(0, 0, canvas.width, canvas.height);

  let destroyed = false;
  let loaded = false;
  let texture = null;
  let imgSize = [1, 1];
  const img = new Image();
  img.addEventListener(
    "load",
    () => {
      if (destroyed) return;
      texture = uploadCoverTexture(gl, img);
      imgSize = [img.naturalWidth || 1, img.naturalHeight || 1];
      loaded = true;
    },
    { once: true },
  );
  img.src = covers[0];

  let elapsed = 0; // own clock — frame() only receives dt, not absolute time

  function frame(dtMs, _phase, attractor) {
    if (destroyed || !loaded) return;
    elapsed += (dtMs || 0) / 1000;

    // Each lens follows a flock member (they wander chaotically and the
    // controller's separation pass keeps them from colliding).
    const flock = (attractor && attractor.flock && attractor.flock.length
      ? attractor.flock
      : [attractor || { x: 0.5, y: 0.5, impulse: 0 }]).slice(0, lensCount);
    const focus = new Float32Array(6);
    const radii = new Float32Array(3);
    flock.forEach((body, i) => {
      // gl_FragCoord is bottom-up; body.y is top-left-origin, so flip it.
      focus[i * 2] = body.x * canvas.width;
      focus[i * 2 + 1] = (1 - body.y) * canvas.height;
      const impulse = Math.max(0, Math.min(1, body.impulse || 0));
      radii[i] = radiusKnob * SIZE_TIERS[i] * (1 + impulse * IMPULSE_WIDEN);
    });

    gl.useProgram(prog);
    gl.bindVertexArray(vao);
    gl.uniform2f(u.res, canvas.width, canvas.height);
    gl.uniform1f(u.time, elapsed);
    gl.uniform1fv(u.radius, radii);
    gl.uniform2fv(u.focus, focus);
    gl.uniform1i(u.count, flock.length);
    gl.uniform2f(u.imgSize, imgSize[0], imgSize[1]);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.uniform1i(u.image, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  function resize(w, h) {
    canvas.width = Math.max(1, Math.round(w * pixelRatio));
    canvas.height = Math.max(1, Math.round(h * pixelRatio));
    gl.viewport(0, 0, canvas.width, canvas.height);
  }

  function ready() {
    return loaded;
  }

  function destroy() {
    if (destroyed) return;
    destroyed = true;
    if (texture) gl.deleteTexture(texture);
    gl.deleteVertexArray(vao);
    gl.deleteProgram(prog);
    const loseCtx = gl.getExtension("WEBGL_lose_context");
    if (loseCtx) loseCtx.loseContext();
  }

  return { canvas, frame, resize, ready, destroy };
}

export default { create };
