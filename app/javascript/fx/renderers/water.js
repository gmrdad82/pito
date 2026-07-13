// water.js — the water mood: a height-field ripple sim that refracts the
// game cover, specular glints on the crests, freezes when idle. Ported from
// pitomd's fx-webgl.js water() (WATER_SIM_FRAG ~L201, WATER_DRAW_FRAG ~L225,
// factory ~L245-427, uploadCoverTexture ~L169-193, GL boilerplate ~L64-132),
// self-contained per THE RENDERER CONTRACT in ./index.js: no imports, no DOM
// queries outside this module's own canvas, no listeners, WebGL2-only, null
// when the environment can't run it.

const WATER_VERT = `#version 300 es
in vec2 p; out vec2 uv;
void main(){ uv = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }`;

const WATER_SIM_FRAG = `#version 300 es
precision highp float;
uniform sampler2D u_prev;
uniform vec2 u_texel;
uniform vec4 u_drop;   /* x,y = uv; z = radius (uv); w = strength */
uniform float u_damping;
in vec2 uv; out vec4 o;
void main(){
  vec2 h = texture(u_prev, uv).rg;   /* r = height, g = previous height */
  float sum =
    texture(u_prev, uv + vec2( u_texel.x, 0.0)).r +
    texture(u_prev, uv - vec2( u_texel.x, 0.0)).r +
    texture(u_prev, uv + vec2(0.0,  u_texel.y)).r +
    texture(u_prev, uv - vec2(0.0,  u_texel.y)).r;
  float next = (sum * 0.5 - h.g) * u_damping;
  if (u_drop.w != 0.0) {
    float d = distance(uv, u_drop.xy);
    next += u_drop.w * exp(-d * d / (u_drop.z * u_drop.z));
  }
  o = vec4(next, h.r, 0.0, 1.0);
}`;

const WATER_DRAW_FRAG = `#version 300 es
precision highp float;
uniform sampler2D u_height;
uniform sampler2D u_image;
uniform vec2 u_texel;
uniform vec2 u_cover;  /* cover-fit scale for the image */
in vec2 uv; out vec4 o;
void main(){
  float hx = texture(u_height, uv + vec2(u_texel.x, 0.0)).r -
             texture(u_height, uv - vec2(u_texel.x, 0.0)).r;
  float hy = texture(u_height, uv + vec2(0.0, u_texel.y)).r -
             texture(u_height, uv - vec2(0.0, u_texel.y)).r;
  vec2 refr = vec2(hx, hy) * 0.06;
  vec2 iuv = (uv - 0.5) * u_cover + 0.5 + refr;
  vec3 col = texture(u_image, iuv).rgb;
  float spec = pow(clamp(1.0 - abs(hx * 14.0 + hy * 10.0), 0.0, 1.0), 24.0);
  col += (hx + hy) * 1.4 + spec * 0.05;
  o = vec4(col, 1.0);
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

const SIM_MAX = 128; // sim grid resolution; bilinear draw smooths the coarser grid
const DROP_MIN_MS = 66; // splat cap ~15/s, mirrors the reference's throttle
const SETTLE_MS = 2000; // no energy for this long -> the field reads as flat
const MOVE_THRESHOLD = 0.003; // attractor motion below this doesn't wake a drop
const IMPULSE_SPLASH = 0.6; // above this the drop lands as a bigger splash
const DEFAULT_DAMPING = 0.94;

function create({ width, height, dpr, knobs, covers }) {
  if (!covers || covers.length === 0) return null;

  const canvas = document.createElement("canvas");
  const gl = canvas.getContext("webgl2");
  if (!gl) return null;
  if (!gl.getExtension("EXT_color_buffer_float")) return null;

  const damping =
    knobs && typeof knobs.damping === "number"
      ? knobs.damping
      : DEFAULT_DAMPING;

  let simProg, drawProg, vao;
  try {
    simProg = linkProgram(gl, WATER_VERT, WATER_SIM_FRAG);
    drawProg = linkProgram(gl, WATER_VERT, WATER_DRAW_FRAG);
    vao = bindFullscreenTriangle(gl, [simProg, drawProg]);
  } catch (_e) {
    return null;
  }

  const u = {
    simPrev: gl.getUniformLocation(simProg, "u_prev"),
    simTexel: gl.getUniformLocation(simProg, "u_texel"),
    simDrop: gl.getUniformLocation(simProg, "u_drop"),
    simDamping: gl.getUniformLocation(simProg, "u_damping"),
    drawHeight: gl.getUniformLocation(drawProg, "u_height"),
    drawImage: gl.getUniformLocation(drawProg, "u_image"),
    drawTexel: gl.getUniformLocation(drawProg, "u_texel"),
    drawCover: gl.getUniformLocation(drawProg, "u_cover"),
  };

  function makeSimTex(w, h) {
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RG16F,
      w,
      h,
      0,
      gl.RG,
      gl.HALF_FLOAT,
      null,
    );
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return tex;
  }
  function makeFbo(tex) {
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(
      gl.FRAMEBUFFER,
      gl.COLOR_ATTACHMENT0,
      gl.TEXTURE_2D,
      tex,
      0,
    );
    return fb;
  }

  const aspect0 = height > 0 ? width / height : 1;
  let simW, simH;
  if (aspect0 >= 1) {
    simW = SIM_MAX;
    simH = Math.max(32, Math.round(SIM_MAX / aspect0));
  } else {
    simH = SIM_MAX;
    simW = Math.max(32, Math.round(SIM_MAX * aspect0));
  }

  let texA = makeSimTex(simW, simH);
  let texB = makeSimTex(simW, simH);
  let fbA = makeFbo(texA);
  let fbB = makeFbo(texB);
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);

  const pixelRatio = dpr || 1;
  canvas.width = Math.max(1, Math.round(width * pixelRatio));
  canvas.height = Math.max(1, Math.round(height * pixelRatio));

  let destroyed = false;
  let loaded = false;
  let imageTex = null;
  const img = new Image();
  img.addEventListener(
    "load",
    () => {
      if (destroyed) return;
      imageTex = uploadCoverTexture(gl, img);
      loaded = true;
    },
    { once: true },
  );
  img.src = covers[0];

  // continuous attractor wake only — a drop is injected only when the
  // attractor has actually moved since the last drop (so a slow drift still
  // accumulates toward the threshold instead of slipping under it every
  // frame), or when its impulse spikes past IMPULSE_SPLASH regardless of
  // motion (a deliberate "splash" beat rather than a drag wake).
  // Drop feel rides fx.yml knobs (owner round 4: a pond, not a downpour) —
  // interval gates the rain, radius fattens the wave, strength whispers it.
  const dropIntervalMs =
    knobs && typeof knobs.drop_interval_ms === "number" ? knobs.drop_interval_ms : DROP_MIN_MS;
  const dropStrength =
    knobs && typeof knobs.drop_strength === "number" ? knobs.drop_strength : 0.22;
  const dropRadius =
    knobs && typeof knobs.drop_radius === "number" ? knobs.drop_radius : 0.012;
  const drop = { x: 0, y: 0, r: dropRadius, s: 0 };
  let lastAx = null;
  let lastAy = null;
  let lastDropAt = null; // null = just created/resized: run until the first settle
  let lastStepAt = 0;
  let elapsed = 0; // own clock — frame() only receives dt, not absolute time

  function coverScale() {
    const iw = img.naturalWidth || 1920;
    const ih = img.naturalHeight || 1080;
    const scale = Math.max(canvas.width / iw, canvas.height / ih);
    return [canvas.width / (iw * scale), canvas.height / (ih * scale)];
  }

  function frame(dtMs, _phase, attractor) {
    if (destroyed || !loaded) return;
    elapsed += dtMs || 0;
    const now = elapsed;

    if (attractor) {
      const ax = attractor.x;
      const ay = attractor.y;
      const moved =
        lastAx === null ||
        Math.abs(ax - lastAx) > MOVE_THRESHOLD ||
        Math.abs(ay - lastAy) > MOVE_THRESHOLD;
      const bigSplash = (attractor.impulse || 0) > IMPULSE_SPLASH;
      if (
        (moved || bigSplash) &&
        (lastDropAt === null || now - lastDropAt > dropIntervalMs)
      ) {
        drop.x = ax;
        drop.y = ay;
        drop.s = bigSplash ? dropStrength * 1.8 : dropStrength;
        lastAx = ax;
        lastAy = ay;
        lastDropAt = now;
      }
    }

    // cap sim steps at ~60fps of sim work even under a faster host loop
    if (now - lastStepAt < 15) return;
    // idle freeze: once no new energy has arrived for SETTLE_MS the field is
    // flat — skip sim AND draw entirely (the canvas keeps its last presented
    // frame) until the next drop or a resize wakes it.
    if (lastDropAt === null) lastDropAt = now;
    else if (now - lastDropAt > SETTLE_MS) return;
    lastStepAt = now;

    gl.bindVertexArray(vao);

    gl.useProgram(simProg);
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbB);
    gl.viewport(0, 0, simW, simH);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texA);
    gl.uniform1i(u.simPrev, 0);
    gl.uniform2f(u.simTexel, 1 / simW, 1 / simH);
    gl.uniform4f(u.simDrop, drop.x, drop.y, drop.r, drop.s);
    gl.uniform1f(u.simDamping, damping);
    drop.s = 0;
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    [texA, texB] = [texB, texA];
    [fbA, fbB] = [fbB, fbA];

    gl.useProgram(drawProg);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texA);
    gl.uniform1i(u.drawHeight, 0);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, imageTex);
    gl.uniform1i(u.drawImage, 1);
    gl.uniform2f(u.drawTexel, 1 / simW, 1 / simH);
    const [cx, cy] = coverScale();
    gl.uniform2f(u.drawCover, cx, cy);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  function resize(w, h) {
    canvas.width = Math.max(1, Math.round(w * (dpr || 1)));
    canvas.height = Math.max(1, Math.round(h * (dpr || 1)));
    // resizing clears the canvas — wake for one settle cycle to repaint
    lastDropAt = null;
  }

  function ready() {
    return loaded;
  }

  function destroy() {
    if (destroyed) return;
    destroyed = true;
    gl.deleteFramebuffer(fbA);
    gl.deleteFramebuffer(fbB);
    gl.deleteTexture(texA);
    gl.deleteTexture(texB);
    if (imageTex) gl.deleteTexture(imageTex);
    gl.deleteVertexArray(vao);
    gl.deleteProgram(simProg);
    gl.deleteProgram(drawProg);
    const loseCtx = gl.getExtension("WEBGL_lose_context");
    if (loseCtx) loseCtx.loseContext();
  }

  return { canvas, frame, resize, ready, destroy };
}

export default { create };
