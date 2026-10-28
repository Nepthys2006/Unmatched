/* Unmatched 3D board.
   Draws one of the 3D Map battlefields (assets/maps3d/<id>.glb) and the live pieces on it. The
   Flutter match screen drives it with JSON messages; the rules never run here. The page takes no
   input of its own: the game handles every touch and click (so its buttons always win) and sends
   camera moves and taps here. Map coordinates: maps.json x -> world x, y -> world z, top at y 0.

   Flutter -> page (window.board.receive(json), WebView2 web messages, or iframe postMessage):
     init   {art|glb, home, gfx, spaces:[{id,x,y}], links:[[a,b]]}  gfx {graphics settings}
            art {file, w, h, unitPx}: a printed map drawn on a slab (glb: a 3D Map model)
     state  {fighters:[{id,space,color,hero,hp,name,mini,fid,v,ranged}], marks:{...,subjectSpace}, tokens:[...], focus:[id]}
            (mini: hero id, fid: fighter id, v: which of a hero's hero fighters; they pick the figure)
     move   {id, path:[space], ms}        fx {id, text, color, sparks, ms}        shake {}
     cam    {op:'fit'|'zoom'|'push'|'pull'|'turn'|'tilt', k, a, b, ms}
     drag {dx, dy} / orbit {dx, dy} (fractions of the view) / pinch {k, a, fx, fy} / pick {x, y}
     fling {vx, vy} (fractions of the view per second, when a slide is let go)
   Page -> Flutter: loaded, ready, progress {p}, error {msg}, tap {x, y}, fps {v}. */
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';

const V3 = THREE.Vector3;
const TAU = Math.PI * 2;
const SELECT = 0x9bea5c, TARGET = 0xff5b4e, BONE = 0xece6d8;
const ease = t => t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

/* ---------------------------------------------------------------- bridge */
function post(msg) {
  const s = JSON.stringify(msg);
  try {
    if (window.FlutterBoard && window.FlutterBoard.postMessage) window.FlutterBoard.postMessage(s);
    else if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(s);
    else if (window.parent !== window) window.parent.postMessage('board3d:' + s, '*');
  } catch (e) { /* no host: opened on its own */ }
}
window.addEventListener('error', e => post({ t: 'error', msg: String(e.message || e) }));
window.addEventListener('unhandledrejection', e => post({ t: 'error', msg: String(e.reason && e.reason.message || e.reason) }));

/* ---------------------------------------------------------------- graphics settings
   scale: render resolution as a share of the screen's pixels (up to 3x, within the tier's pixel
   budget); auto: let the frame-time governor trade resolution and effects for a steady 60 fps;
   shadows 0-3 (off / 1024 / 2048 / 4096); aa: multisampling; bloom: glow; ao: ambient occlusion;
   scenery: trees, rocks and buildings; brightness: exposure; labels: name plate size;
   tier 0-3: the quality preset (Low..Ultra), which sets texture, figure and badge detail. */
const G = { scale: 1, auto: true, shadows: 2, aa: true, bloom: true, ao: false, scenery: true, brightness: 1, labels: 1, fps: false, tier: 2 };
const SHADOW_SIZE = [512, 1024, 2048, 4096];
const DPR = () => clamp(window.devicePixelRatio || 1, 1, 3);
/* Per tier: most pixels drawn per frame (millions), how sharp the figures' pictures are upscaled
   (longest side, 0 = as shipped), the relief's detail grid, badge/number canvas density, and how
   often idle highlights (pulses with nothing else moving) are redrawn. */
const TIER = [
  { budget: 2.0, figure: 0, grid: 110, coin: 64, label: 1, idleFps: 20, maxAniso: 1, dprCap: 1.5 },
  { budget: 3.7, figure: 640, grid: 140, coin: 72, label: 1.5, idleFps: 30, maxAniso: 4, dprCap: 1.5 },
  { budget: 8.3, figure: 900, grid: 160, coin: 80, label: 2, idleFps: 60, maxAniso: 8, dprCap: 2.0 },
  { budget: 12.5, figure: 1200, grid: 190, coin: 96, label: 2.5, idleFps: 60, maxAniso: 16, dprCap: 3.0 },
];

function tierAniso(cap = 16) {
  if (!renderer) return 1;
  const devMax = renderer.capabilities.getMaxAnisotropy();
  return Math.min(tier().maxAniso, cap, devMax);
}

/* ---------------------------------------------------------------- CAS Sharpening */
const CASShader = {
  name: 'CASShader',
  uniforms: {
    tDiffuse: { value: null },
    resolution: { value: new THREE.Vector2(1, 1) },
    sharpness: { value: 0.5 },
  },
  vertexShader: `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  fragmentShader: `
    uniform sampler2D tDiffuse;
    uniform vec2 resolution;
    uniform float sharpness;
    varying vec2 vUv;

    void main() {
      vec2 step = 1.0 / resolution;
      vec3 a = texture2D(tDiffuse, vUv + vec2(0.0, -step.y)).rgb;
      vec3 b = texture2D(tDiffuse, vUv + vec2(-step.x, 0.0)).rgb;
      vec3 c = texture2D(tDiffuse, vUv).rgb;
      vec3 d = texture2D(tDiffuse, vUv + vec2(step.x, 0.0)).rgb;
      vec3 e = texture2D(tDiffuse, vUv + vec2(0.0, step.y)).rgb;

      vec3 min_rgb = min(min(min(a, b), min(d, e)), c);
      vec3 max_rgb = max(max(max(a, b), max(d, e)), c);

      vec3 w = sqrt(min(min_rgb, 2.0 - max_rgb) / max(max_rgb, 0.001));
      vec3 peak = -1.0 / mix(8.0, 5.0, clamp(sharpness, 0.0, 1.0));
      vec3 weight = w * peak;

      vec3 color = (a + b + d + e) * weight + c;
      gl_FragColor = vec4(clamp(color / (1.0 + 4.0 * weight), 0.0, 1.0), 1.0);
    }
  `,
};

/* ---------------------------------------------------------------- Hardware Starting Tier */
function detectHardwareTier() {
  try {
    const saved = localStorage.getItem('unmatched_gpu_tier');
    if (saved !== null) {
      const v = parseInt(saved, 10);
      if (!isNaN(v) && v >= 0 && v <= 3) return v;
    }
  } catch (_) {}

  let str = '';
  try {
    const gl = renderer ? renderer.getContext() : null;
    if (gl) {
      const dbg = gl.getExtension('WEBGL_debug_renderer_info');
      if (dbg) str = (gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) || '').toLowerCase();
    }
  } catch (_) {}

  let t = 2; // Default High
  if (str) {
    if (str.includes('rtx') || str.includes('radeon rx') || str.includes('apple m1 pro') ||
        str.includes('apple m2') || str.includes('apple m3') || str.includes('apple m4') ||
        str.includes('gtx 1080') || str.includes('gtx 1660') || str.includes('gtx 1070')) {
      t = 3; // Ultra
    } else if (str.includes('iris') || str.includes('adreno (tm) 6') || str.includes('adreno (tm) 7') ||
               str.includes('mali-g7') || str.includes('apple a1') || str.includes('gtx 1050') ||
               str.includes('gtx 1060')) {
      t = 2; // High
    } else if (str.includes('mali') || str.includes('adreno') || str.includes('intel hd') ||
               str.includes('powervr') || str.includes('swiftshader') || str.includes('llvmpipe')) {
      t = 0; // Low
    }
  } else if ((typeof navigator !== 'undefined' && navigator.maxTouchPoints > 0) || innerWidth < 700) {
    t = 1; // Medium for mobile
  }
  return t;
}

let warmupFrames = 0, warmupTotalMs = 0, warmupBenchDone = false;
function stepWarmupBench(frameMs) {
  if (warmupBenchDone || !loaded) return;
  warmupFrames++;
  warmupTotalMs += frameMs;
  if (warmupFrames >= 75) {
    warmupBenchDone = true;
    const avg = warmupTotalMs / warmupFrames;
    let rec = G.tier;
    if (avg > 24) rec = Math.max(0, G.tier - 1);
    else if (avg < 11 && G.tier < 3) rec = Math.min(3, G.tier + 1);
    try { localStorage.setItem('unmatched_gpu_tier', String(rec)); } catch (_) {}
    if (rec !== G.tier) {
      applyGfx({ tier: rec });
      post({ t: 'tierChanged', tier: rec });
    }
  }
}
const tier = () => TIER[clamp(G.tier | 0, 0, 3)];
let prMax = 1, prNow = 1, prMin = .5;

/* ---------------------------------------------------------------- scene */
let renderer, scene, camera, lamp, composer = null;
let boardRoot = null, span = 14, box = new THREE.Box3();
const spaces = new Map();        // id -> {x, z, top}
let links = [];
let homeSide = 1;
let loaded = false, pendingState = null;
let dirty = 2;
let loopActive = false, loopId = null;

function wakeLoop() {
  if (loopActive || (typeof document !== 'undefined' && document.hidden)) return;
  loopActive = true;
  nextFrame = performance.now();
  loopId = requestAnimationFrame(loop);
}

function pauseLoop() {
  if (loopId != null) {
    cancelAnimationFrame(loopId);
    loopId = null;
  }
  loopActive = false;
}

const invalidate = (n = 2) => {
  dirty = Math.max(dirty, n);
  wakeLoop();
};

function setup() {
  try {
    // No multisampling on the canvas: antialiasing happens in the composer's target, so it can
    // follow the resolution and be changed while the page runs.
    renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance', stencil: false });
  } catch (e) {
    post({ t: 'error', fatal: true, msg: 'WebGL is not available' });
    return false;
  }
  renderer.setSize(innerWidth, innerHeight);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.shadowMap.autoUpdate = false;
  document.body.appendChild(renderer.domElement);

  scene = new THREE.Scene();
  scene.background = new THREE.Color('#0e0f12');
  scene.fog = new THREE.Fog('#0e0f12', 40, 90);
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), .04).texture;
  scene.environmentIntensity = .42;

  camera = new THREE.PerspectiveCamera(34, innerWidth / innerHeight, .1, 260);

  // A warm table lamp, a cool fill and a faint bounce, as on the 3D Map table.
  scene.add(new THREE.HemisphereLight('#dfe6ff', '#2b1d12', .3));
  lamp = new THREE.SpotLight('#ffd2a0', 100, 0, .7, .85, 2);
  lamp.shadow.bias = -.00015;
  lamp.shadow.normalBias = .025;
  const fill = new THREE.DirectionalLight('#a9bfff', .38);
  scene.add(lamp, lamp.target, fill);
  scene.userData.fill = fill;

  addEventListener('resize', () => {
    camera.aspect = innerWidth / Math.max(1, innerHeight);
    camera.updateProjectionMatrix();
    applyResolution(true); // the pixel budget depends on the window's size
    buildComposer();
  });
  applyResolution();
  wakeLoop();
  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        pauseLoop();
      } else {
        invalidate(3);
        wakeLoop();
      }
    });
  }
  return true;
}

/** Full resolution is the screen's own pixels (phones up to 3x) times the chosen scale, kept within
    the tier's pixel budget so a big, dense screen can't sink the frame rate. `keep` holds the
    governor's current step (a resize); otherwise it starts again from full resolution. */
function applyResolution(keep) {
  const css = Math.max(1, innerWidth * innerHeight);
  const fit = Math.sqrt(tier().budget * 1e6 / css);
  const targetDpr = Math.min(DPR(), tier().dprCap || 3.0);
  prMax = clamp(Math.min(targetDpr * G.scale, fit, 3), .5, 3);
  prMin = Math.min(prMax, Math.max(.6, prMax * .6));
  if (!keep) gov.level = 0;
  setPixelRatio(G.auto ? clamp(prMax * RES_STEP[govRes()], prMin, prMax) : prMax);
}

function setPixelRatio(pr) {
  prNow = pr;
  renderer.setPixelRatio(prNow);
  renderer.setSize(innerWidth, innerHeight);
  if (composer) { composer.setPixelRatio(prNow); composer.setSize(innerWidth, innerHeight); }
  invalidate();
}

/** The effects actually drawn: the settings, less what the governor has turned off for speed. */
const fxOn = () => ({ bloom: G.bloom && !(G.auto && gov.level >= GOV_NO_BLOOM), ao: G.ao && !(G.auto && gov.level >= GOV_NO_AO) });
let built = { bloom: null, ao: null, aa: null, samples: null };

/** The scene renders into a multisampled half-float target, then bloom and ambient occlusion when
    on, then tone mapping. With no antialiasing and no effects it renders straight out. MSAA
    samples follow the resolution: a 3x phone screen is already supersampled, so it skips them
    (and the memory they'd take); bloom and AO run at no more than the screen's CSS resolution. */
let casPass = null;

function buildComposer() {
  const fx = fxOn();
  const samples = !G.aa ? 0 : prMax >= 2.5 ? 0 : prMax >= 1.5 ? 2 : 4;
  const needCas = G.auto && (gov.level > 0 || prNow < prMax * 0.98);
  if (built.bloom === fx.bloom && built.ao === fx.ao && built.aa === G.aa && built.samples === samples && built.cas === needCas) return;
  built = { bloom: fx.bloom, ao: fx.ao, aa: G.aa, samples, cas: needCas };
  disposeComposer();
  for (const p of pieces.values()) sizePiece(p);
  if (!fx.bloom && !fx.ao && !G.aa && !needCas) return;
  const rt = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples });
  composer = new EffectComposer(renderer, rt);
  composer.setPixelRatio(prNow);
  composer.setSize(innerWidth, innerHeight);
  composer.addPass(new RenderPass(scene, camera));
  if (fx.ao) {
    const ao = new GTAOPass(scene, camera, innerWidth, innerHeight);
    ao.blendIntensity = .85;
    ao.updateGtaoMaterial({ radius: .32, distanceExponent: 1.4, thickness: 1, scale: 1.1, samples: G.tier >= 3 ? 12 : 8 });
    ao.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 4, rings: 2, samples: G.tier >= 3 ? 16 : 12 });
    capPassSize(ao, 1);
    // Its depth/normal pass draws everything but points and lines with one override material,
    // which printed dark boxes of "occlusion" on the table: round the fighters from their tags,
    // glows and highlight rings (sprites and see-through overlays), and in the middle of the
    // board from the backdrop (a texture background is drawn as a 2x2 plane, which the override
    // material puts at the world's origin). All of those sit that pass out.
    const hide = ao.overrideVisibility.bind(ao), show = ao.restoreVisibility.bind(ao);
    let backdrop = null;
    ao.overrideVisibility = () => {
      hide();
      backdrop = scene.background;
      scene.background = null;
      scene.traverse(o => { if (o.isSprite || (o.isMesh && !Array.isArray(o.material) && o.material.transparent)) o.visible = false; });
    };
    ao.restoreVisibility = () => {
      show();
      scene.background = backdrop;
    };
    composer.addPass(ao);
  }
  if (fx.bloom) {
    const bloom = new UnrealBloomPass(new THREE.Vector2(Math.floor(innerWidth / 2), Math.floor(innerHeight / 2)), .32, .5, .88);
    capPassSize(bloom, G.tier >= 3 ? 1.5 : 1);
    composer.addPass(bloom);
  }
  if (needCas) {
    casPass = new ShaderPass(CASShader);
    casPass.uniforms.resolution.value.set(innerWidth * prNow, innerHeight * prNow);
    casPass.uniforms.sharpness.value = clamp(0.35 + (1 - RES_STEP[govRes()]) * 0.8, 0.25, 0.8);
    composer.addPass(casPass);
  } else {
    casPass = null;
  }
  composer.addPass(new OutputPass());
  invalidate();
}

/** EffectComposer.dispose frees only its own two targets; each pass (bloom's mip chain, GTAO's
    buffers) has its own, which leaked every time the effects were rebuilt (a settings change, or
    the governor turning bloom or AO off and on). */
function disposeComposer() {
  if (!composer) return;
  for (const pass of composer.passes) if (pass.dispose) pass.dispose();
  composer.dispose();
  composer = null;
}

/** Runs a soft, full-screen pass at no more than `k` times the CSS resolution (glow and shading
    don't need a 3x phone's pixels; they're upsampled when blended). */
function capPassSize(pass, k) {
  const setSize = pass.setSize.bind(pass);
  pass.setSize = (w, h) => {
    const s = Math.min(1, innerWidth * k / Math.max(1, w));
    setSize(Math.max(1, Math.round(w * s)), Math.max(1, Math.round(h * s)));
  };
}

function applyShadows() {
  const on = G.shadows > 0, size = SHADOW_SIZE[G.shadows] || 1024;
  renderer.shadowMap.enabled = on;
  lamp.castShadow = on;
  if (lamp.shadow.mapSize.x !== size) {
    lamp.shadow.mapSize.set(size, size);
    if (lamp.shadow.map) { lamp.shadow.map.dispose(); lamp.shadow.map = null; }
  }
  scene.traverse(o => {
    if (!o.isMesh) return;
    o.castShadow = on && !!o.userData.casts;
    o.receiveShadow = on && !o.userData.noShadow;
    for (const m of Array.isArray(o.material) ? o.material : [o.material]) if (m) m.needsUpdate = true;
  });
  for (const p of pieces.values()) {
    if (p.blobShadow) p.blobShadow.visible = G.shadows === 0;
  }
  renderer.shadowMap.needsUpdate = true;
  invalidate();
}

/** Applies graphics settings; `first` when the page starts. */
function applyGfx(g, first) {
  const old = { ...G };
  Object.assign(G, g || {});
  if (!renderer) return;
  if (first || old.scale !== G.scale || old.tier !== G.tier || old.auto !== G.auto) {
    applyResolution();
    if (scene) {
      scene.traverse(o => {
        if (!o.isMesh || !o.material) return;
        for (const m of [].concat(o.material)) {
          if (m && m.map) { m.map.anisotropy = tierAniso(); m.map.needsUpdate = true; }
        }
      });
    }
  }
  if (first || old.shadows !== G.shadows) applyShadows();
  buildComposer();
  renderer.toneMappingExposure = G.brightness;
  const scenery = boardRoot && boardRoot.getObjectByName('Scenery');
  if (scenery && scenery.visible !== G.scenery) { scenery.visible = G.scenery; renderer.shadowMap.needsUpdate = true; }
  for (const p of pieces.values()) sizePiece(p);
  invalidate();
}

/* ---------------------------------------------------------------- loading */
async function init(msg) {
  const hardwareTier = detectHardwareTier();
  const incomingGfx = { ...(msg.gfx || {}) };
  if (incomingGfx.tier == null) incomingGfx.tier = hardwareTier;
  Object.assign(G, incomingGfx);
  if (!setup()) return;
  homeSide = msg.home || 1;
  for (const s of msg.spaces) spaces.set(s.id, { x: s.x, z: s.y, top: .003 });
  links = msg.links || [];
  try {
    boardRoot = msg.art ? await artBoard(msg.art) : (await loadGlb(msg.glb)).scene;
  } catch (e) {
    post({ t: 'error', fatal: true, msg: 'Could not load the map: ' + (e && e.message || e) });
    return;
  }
  boardRoot.updateMatrixWorld(true);
  if (!msg.art) boardRoot = mergeStatic(boardRoot); // an art board is a single mesh already
  // Full anisotropic filtering on the board's textures: the camera looks at the table at a slant,
  // where plain mipmapping smears the printed art. (An art board's slab has a material per face.)
  const aniso = renderer.capabilities.getMaxAnisotropy();
  boardRoot.traverse(o => {
    if (!o.isMesh) return;
    o.userData.casts = isUnder(o, 'Scenery');
    for (const m of [].concat(o.material || [])) {
      if (!m.map) continue;
      m.map.anisotropy = tierAniso(16);
      m.map.minFilter = THREE.LinearMipmapLinearFilter;
      m.map.needsUpdate = true;
    }
  });
  scene.add(boardRoot);
  boardRoot.updateMatrixWorld(true);

  // Size, lamp and table follow the board, as in the 3D Map app.
  const boardGroup = boardRoot.getObjectByName('Board') || boardRoot;
  box.setFromObject(boardGroup);
  const W = box.max.x - box.min.x, D = box.max.z - box.min.z;
  span = Math.max(W, D);
  const h = span * .95 + 6;
  lamp.position.set(-W * .32, h, D * .32 + 2);
  lamp.target.position.set(W * .04, 0, -D * .04);
  const d = lamp.position.distanceTo(lamp.target.position);
  lamp.intensity = 3.3 * d * d;
  lamp.angle = Math.atan(span * .78 / h) + .12;
  lamp.shadow.camera.near = h * .5;
  lamp.shadow.camera.far = h * 2.2;
  scene.userData.fill.position.set(W * .6, 6, -D * .8);
  scene.fog.near = span * 2.2;
  scene.fog.far = span * 4.4;
  const table = new THREE.Mesh(
    new THREE.PlaneGeometry(span * 5, span * 5).rotateX(-Math.PI / 2),
    new THREE.MeshStandardMaterial({ color: '#2b2019', roughness: .82 }),
  );
  table.position.y = box.min.y - .002;
  scene.add(table);
  if (msg.art) printedLight(W, D);

  // Where each space's surface is (discs sit on plinths in diorama mode; bridges are raised).
  const ray = new THREE.Raycaster();
  const meshes = [];
  boardRoot.traverse(o => { if (o.isMesh) meshes.push(o); });
  for (const s of spaces.values()) {
    ray.set(new V3(s.x, 4, s.z), new V3(0, -1, 0));
    const hit = ray.intersectObjects(meshes, false).find(h => h.point.y < .35);
    s.top = hit ? hit.point.y + .002 : .003;
  }

  camera.aspect = innerWidth / Math.max(1, innerHeight);
  camera.updateProjectionMatrix();
  const home = homeView();
  setRig(home.pos, home.target);
  syncCamera();
  loaded = true;
  applyGfx(null, true);
  if (pendingState) applyState(pendingState);
  invalidate(3);
  // Two frames so the first picture is on screen before the cover is lifted.
  requestAnimationFrame(() => requestAnimationFrame(() => post({ t: 'ready' })));
}

/** A printed map is lit like the Map Viewer: bright, even, neutral light from above (a sky fill and
    a sun that casts the shadows), true colours (no film tone curve), and a dark table round it.
    The old 3D models keep their warm lamp. */
function printedLight(W, D) {
  renderer.toneMapping = THREE.NoToneMapping;
  scene.environment = null;
  // The app's navy table: a lit backdrop falling off to a dark rim, fog of the rim's colour.
  scene.background = canvasTex(512, 512, (g, w, h) => {
    const r = g.createRadialGradient(w / 2, h * .42, 0, w / 2, h * .42, w * .75);
    r.addColorStop(0, '#1d2533'); r.addColorStop(.55, '#121722'); r.addColorStop(1, '#07090d');
    g.fillStyle = r; g.fillRect(0, 0, w, h);
  });
  scene.fog.color.set('#0a0d13');
  scene.traverse(o => { if (o.isHemisphereLight) { o.color.set('#fff6e8'); o.groundColor.set('#30302c'); o.intensity = 1.9; } });
  scene.userData.fill.intensity = 0;
  // the lamp becomes a sun: white, no fall-off, wide enough to cover the board evenly
  const h = Math.max(W, D) * 1.4 + 6;
  lamp.color.set('#ffffff');
  lamp.decay = 0;
  lamp.distance = 0;
  lamp.intensity = 1.3 * Math.PI;
  lamp.penumbra = 1;
  lamp.position.set(-W * .3, h, D * .4);
  lamp.target.position.set(0, 0, 0);
  lamp.angle = Math.atan(Math.max(W, D) * .9 / h) + .15;
  lamp.shadow.camera.near = h * .5;
  lamp.shadow.camera.far = h * 2;
  scene.traverse(o => {
    if (o.isMesh && o.material && o.material.color && o.geometry.type === 'PlaneGeometry' && o.position.y < 0) {
      o.material.color.set('#ffffff');
      o.material.map = feltTexture();
      o.material.roughness = .95;
      o.material.needsUpdate = true;
    }
  });
}

/* The table cloth: navy felt with a fine grain, lit in a pool under the board and falling off to
   the rim (baked in, so it costs one texture lookup). Made once, on first use. */
let feltTex = null;
function feltTexture() {
  if (!feltTex) {
    feltTex = canvasTex(1024, 1024, (g, w, h) => {
      const r = g.createRadialGradient(w / 2, h / 2, w * .04, w / 2, h / 2, w * .5);
      r.addColorStop(0, '#2b364b'); r.addColorStop(.22, '#1d2535'); r.addColorStop(.5, '#111622'); r.addColorStop(1, '#090c12');
      g.fillStyle = r; g.fillRect(0, 0, w, h);
      // grain: faint light and dark flecks
      const img = g.getImageData(0, 0, w, h), d = img.data;
      let seed = 7;
      const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
      for (let i = 0; i < d.length; i += 4) {
        const n = (rnd() - .5) * 14;
        d[i] = clamp(d[i] + n, 0, 255); d[i + 1] = clamp(d[i + 1] + n, 0, 255); d[i + 2] = clamp(d[i + 2] + n * 1.1, 0, 255);
      }
      g.putImageData(img, 0, 0);
    });
    feltTex.anisotropy = tierAniso(8);
  }
  return feltTex;
}

function loadGlb(url) {
  const loader = new GLTFLoader();
  loader.setMeshoptDecoder(MeshoptDecoder);
  return loader.loadAsync(url, e => { if (e.total) post({ t: 'progress', p: e.loaded / e.total }); });
}

/** A printed map as a board on the table: its art on top of a thin slab with a dark edge, the same
    as the Map Viewer's flat GLBs. Map units are art pixels / unitPx from the picture's centre, so
    the spaces land on the painted circles. */
async function artBoard(art) {
  const tex = await new THREE.TextureLoader().loadAsync(art.file);
  post({ t: 'progress', p: 1 });
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = tierAniso(16);
  const W = art.w / art.unitPx, D = art.h / art.unitPx, T = .14;
  const edge = new THREE.MeshStandardMaterial({ color: '#1d1c1a', roughness: .8 });
  const top = new THREE.MeshStandardMaterial({ map: tex, roughness: .82 });
  const slab = new THREE.Mesh(new THREE.BoxGeometry(W, T, D), [edge, edge, top, edge, edge, edge]);
  slab.position.y = -T / 2;
  const board = new THREE.Group();
  board.name = 'Board';
  board.add(slab);
  const root = new THREE.Group();
  root.add(board);
  return root;
}

/* The exported maps have ~190 meshes over ~35 materials. Nothing on the table moves, so meshes
   sharing a material are baked into one: a handful of draw calls instead of hundreds, which is
   what keeps phones at 60 fps. Quantized (meshopt) attributes are expanded to floats first. */
function mergeStatic(root) {
  const groups = new Map();
  root.traverse(o => {
    if (!o.isMesh || Array.isArray(o.material)) return;
    const part = isUnder(o, 'Scenery') ? 'Scenery' : 'Board';
    const keyAttrs = Object.keys(o.geometry.attributes).sort().join(',');
    const key = part + '|' + o.material.uuid + '|' + keyAttrs + '|' + (o.geometry.index ? 1 : 0);
    if (!groups.has(key)) groups.set(key, { part, material: o.material, meshes: [] });
    groups.get(key).meshes.push(o);
  });
  const out = new THREE.Group();
  const parts = { Board: new THREE.Group(), Scenery: new THREE.Group() };
  parts.Board.name = 'Board'; parts.Scenery.name = 'Scenery';
  out.add(parts.Board, parts.Scenery);
  for (const g of groups.values()) {
    const geos = g.meshes.map(m => {
      const geo = new THREE.BufferGeometry();
      for (const [name, a] of Object.entries(m.geometry.attributes)) {
        const arr = new Float32Array(a.count * a.itemSize);
        for (let i = 0; i < a.count; i++) for (let k = 0; k < a.itemSize; k++) arr[i * a.itemSize + k] = a.getComponent(i, k);
        geo.setAttribute(name, new THREE.BufferAttribute(arr, a.itemSize));
      }
      if (m.geometry.index) geo.setIndex(Array.from(m.geometry.index.array));
      geo.applyMatrix4(m.matrixWorld);
      return geo;
    });
    let merged = geos.length > 1 ? mergeGeometries(geos, false) : geos[0];
    if (!merged) { // attribute mismatch: keep them separate
      g.meshes.forEach((m, i) => { const mm = new THREE.Mesh(geos[i], g.material); parts[g.part].add(mm); });
      continue;
    }
    if (merged !== geos[0]) geos.forEach(x => x.dispose());
    merged.computeBoundingSphere();
    parts[g.part].add(new THREE.Mesh(merged, g.material));
  }
  root.traverse(o => { if (o.isMesh) o.geometry.dispose(); });
  return out;
}

function isUnder(o, name) {
  for (let p = o; p; p = p.parent) if (p.name === name) return true;
  return false;
}

/* ---------------------------------------------------------------- camera
   A simple rig: a target on the board and the camera on a sphere around it (r, phi from
   straight down... up, theta around). The game sends drags, pinches, orbits and flicks; they
   move the `goal`, and the camera glides after it every frame (exponential smoothing, the same
   feel at any frame rate), so uneven touch events and mouse-wheel notches come out as one fluid
   motion. A flick keeps the board sliding and slowing. Scripted moves (fit, push-in for a
   duel, pull back, turn, tilt) are timed tweens that the goal follows. */
let camTween = null, shakeUntil = 0, preCombat = null;
const rig = { target: new V3(), r: 20, phi: .62, theta: 0 };
const goal = { target: new V3(), r: 20, phi: .62, theta: 0 };
const fling = new V3();          // board slide after a flick, world units per second
const CAM_TAU = .07;             // seconds for the camera to close ~63% of the gap to the goal
const FLING_DRAG = 4.2;          // how fast a flick slows (per second)
const PHI_MIN = .08, PHI_MAX = 1.3, R_MIN = 2.5;
const rMax = () => span * 2.2;
const spherical = (target, dist, polar, azim) =>
  target.clone().add(new V3(Math.sin(polar) * Math.sin(azim), Math.cos(polar), Math.sin(polar) * Math.cos(azim)).multiplyScalar(dist));

function setRig(pos, target) {
  const o = pos.clone().sub(target);
  rig.target.copy(target);
  rig.r = Math.max(1e-3, o.length());
  rig.phi = Math.acos(clamp(o.y / rig.r, -1, 1));
  rig.theta = Math.atan2(o.x, o.z);
  goalToRig();
}

function goalToRig() {
  goal.target.copy(rig.target); goal.r = rig.r; goal.phi = rig.phi; goal.theta = rig.theta;
}

function clampTarget(t) {
  if (box.isEmpty()) return;
  t.x = clamp(t.x, box.min.x - 3, box.max.x + 3);
  t.z = clamp(t.z, box.min.z - 3, box.max.z + 3);
}

/** Input takes over from a scripted move where the camera is now. */
function takeControl() {
  if (camTween) { camTween = null; goalToRig(); }
  invalidate();
}

function syncCamera() {
  clampTarget(rig.target);
  camera.position.copy(spherical(rig.target, rig.r, rig.phi, rig.theta));
  camera.lookAt(rig.target);
  invalidate();
}

/** World size of the view at the goal's distance, and its ground axes. */
function goalAxes() {
  const k = 2 * goal.r * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  const right = new V3(Math.cos(goal.theta), 0, -Math.sin(goal.theta));
  const fwd = new V3(-Math.sin(goal.theta), 0, -Math.cos(goal.theta));
  return { k, right, fwd, along: k / Math.max(.35, Math.cos(goal.phi)) };
}

/** One finger / left button: slide the board under the finger. */
function drag(dx, dy) {
  takeControl();
  fling.set(0, 0, 0);
  const { k, right, fwd, along } = goalAxes();
  goal.target.addScaledVector(right, -dx * k * camera.aspect).addScaledVector(fwd, dy * along);
  clampTarget(goal.target);
}
/** The finger left the board moving (fractions of the view per second): let it glide on. */
function flick(vx, vy) {
  const { k, right, fwd, along } = goalAxes();
  fling.set(0, 0, 0).addScaledVector(right, -vx * k * camera.aspect).addScaledVector(fwd, vy * along);
  const max = span * 2.5;
  if (fling.length() > max) fling.setLength(max);
  invalidate();
}
/** Right button: turn around the board and tilt. */
function orbit(dx, dy) {
  takeControl();
  goal.theta -= dx * Math.PI * 1.4;
  goal.phi = clamp(goal.phi - dy * Math.PI * .8, PHI_MIN, PHI_MAX);
}
/** Two fingers or the wheel: zoom (k > 1 = closer) toward the point under (fx, fy) (fractions of
    the view; the view's centre if absent) and twist to turn. */
function pinch(k, a, fx, fy) {
  takeControl();
  fling.set(0, 0, 0);
  const r0 = goal.r;
  goal.r = clamp(goal.r / k, R_MIN, rMax());
  goal.theta -= a || 0;
  if (fx != null && fy != null) {
    const p = groundAt(fx, fy);
    if (p) {
      const f = 1 - goal.r / r0;
      goal.target.x += (p.x - goal.target.x) * f;
      goal.target.z += (p.z - goal.target.z) * f;
      clampTarget(goal.target);
    }
  }
}
const groundRay = new THREE.Raycaster(), groundPlane = new THREE.Plane(new V3(0, 1, 0), 0);
function groundAt(fx, fy) {
  groundRay.setFromCamera(new THREE.Vector2(fx * 2 - 1, 1 - fy * 2), camera);
  return groundRay.ray.intersectPlane(groundPlane, new V3());
}

/** Moves the camera toward the goal; true while it's still moving. */
function stepCamera(dt) {
  if (camTween || !loaded) return false;
  let moving = false;
  if (fling.lengthSq() > 0) {
    goal.target.addScaledVector(fling, dt);
    clampTarget(goal.target);
    fling.multiplyScalar(Math.exp(-dt * FLING_DRAG));
    if (fling.length() < span * .004) fling.set(0, 0, 0);
    moving = true;
  }
  const gap = goal.target.distanceTo(rig.target) / rig.r + Math.abs(Math.log(goal.r / rig.r)) +
    Math.abs(goal.phi - rig.phi) + Math.abs(goal.theta - rig.theta);
  if (gap === 0) return moving;
  if (gap < 2e-4) {
    rig.target.copy(goal.target); rig.r = goal.r; rig.phi = goal.phi; rig.theta = goal.theta;
  } else {
    const a = 1 - Math.exp(-dt / CAM_TAU);
    rig.target.lerp(goal.target, a);
    rig.r *= Math.pow(goal.r / rig.r, a); // zoom in log space: the same pace near and far
    rig.phi += (goal.phi - rig.phi) * a;
    rig.theta += (goal.theta - rig.theta) * a;
  }
  syncCamera();
  return true;
}

/** The whole board from the player's side, clear of the prompt bar on top and the hand below. */
function homeView() {
  const polar = .62, azim = homeSide > 0 ? 0 : Math.PI;
  const lim = { x0: -.9, x1: .9, y0: -.66, y1: .8 };
  const corners = [];
  for (const x of [box.min.x, box.max.x]) for (const y of [0, .5]) for (const z of [box.min.z, box.max.z]) corners.push(new V3(x, y, z));
  const target = box.getCenter(new V3()); target.y = 0;
  let dist = span * 1.3;
  const cam = camera.clone();
  const right = new V3(Math.cos(azim), 0, -Math.sin(azim));
  const fwd = new V3(-Math.sin(azim), 0, -Math.cos(azim));
  for (let i = 0; i < 12; i++) {
    cam.position.copy(spherical(target, dist, polar, azim));
    cam.lookAt(target);
    cam.updateMatrixWorld();
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (const c of corners) {
      const p = c.clone().project(cam);
      x0 = Math.min(x0, p.x); x1 = Math.max(x1, p.x); y0 = Math.min(y0, p.y); y1 = Math.max(y1, p.y);
    }
    const s = Math.max((x1 - x0) / (lim.x1 - lim.x0), (y1 - y0) / (lim.y1 - lim.y0));
    const halfH = Math.tan(THREE.MathUtils.degToRad(cam.fov / 2)) * dist, halfW = halfH * cam.aspect;
    const cx = (x0 + x1) / 2 - (lim.x0 + lim.x1) / 2, cy = (y0 + y1) / 2 - (lim.y0 + lim.y1) / 2;
    target.addScaledVector(right, cx * halfW).addScaledVector(fwd, cy * halfH / Math.cos(polar));
    dist *= s;
  }
  return { pos: spherical(target, dist, polar, azim), target };
}

function rigTo(target, r, phi, theta, ms) {
  // Turn the short way round.
  let d = (theta - rig.theta) % TAU;
  if (d > Math.PI) d -= TAU;
  if (d < -Math.PI) d += TAU;
  const to = { target: target.clone(), r, phi, theta: rig.theta + d };
  clampTarget(to.target);
  fling.set(0, 0, 0);
  if (!ms) { rig.target.copy(to.target); rig.r = r; rig.phi = phi; rig.theta = to.theta; goalToRig(); syncCamera(); return; }
  camTween = { from: { target: rig.target.clone(), r: rig.r, phi: rig.phi, theta: rig.theta }, to, start: performance.now(), ms };
  invalidate();
}

function tweenTo(pos, target, ms) {
  const o = pos.clone().sub(target), r = o.length();
  rigTo(target, r, Math.acos(clamp(o.y / r, -1, 1)), Math.atan2(o.x, o.z), ms);
}

function zoom(k) { pinch(k, 0); }
function turn(a) { takeControl(); rigTo(goal.target, goal.r, goal.phi, goal.theta + a, 420); }
/** Toggles between the seated view and looking straight down. */
function tilt() { takeControl(); rigTo(goal.target, goal.r, goal.phi > .3 ? PHI_MIN : .62, goal.theta, 420); }

/** The dramatic push-in: camera faces from the attacker toward the defender. */
function pushIn(a, b, ms) {
  const A = spaces.get(a), B = spaces.get(b);
  if (!A || !B) return;
  preCombat = { pos: camera.position.clone(), target: rig.target.clone() };
  const mid = new V3((A.x + B.x) / 2, (A.top + B.top) / 2 + .25, (A.z + B.z) / 2);
  const along = new V3(B.x - A.x, 0, B.z - A.z);
  const len = along.length();
  // Always face from attacker toward defender (looking along the attack direction).
  const dir = len > 1e-3 ? along.clone().normalize() : new V3(0, 0, -homeSide);
  // Camera sits behind the attacker looking toward the defender without 180 flips.
  const viewVec = dir.clone().negate();
  const polar = 1.05;
  const tanH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  // Frame the duel in the lower part of the screen, beneath the combat cards.
  const dist = clamp((len + 2.4) / (.6 * 2 * tanH * camera.aspect), 6.5, span * .9);
  const azim = Math.atan2(viewVec.x, viewVec.z);
  const target = mid.clone().addScaledVector(viewVec, -.4 * tanH * dist / Math.cos(polar));
  tweenTo(spherical(target, dist, polar, azim), target, ms);
}

function pullBack(ms) {
  if (preCombat) tweenTo(preCombat.pos, preCombat.target, ms);
  preCombat = null;
}

/* ---------------------------------------------------------------- textures */
function canvasTex(w, h, draw) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const GLOW = canvasTex(128, 128, (g, w) => {
  const r = g.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2);
  r.addColorStop(0, 'rgba(255,255,255,1)'); r.addColorStop(.3, 'rgba(255,255,255,.55)');
  r.addColorStop(.6, 'rgba(255,255,255,.16)'); r.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = r; g.fillRect(0, 0, w, w);
});
// A fog puff: a lit cloud ball, grey-blue underneath, so it reads on light and dark boards alike.
const PUFF = canvasTex(128, 128, (g, w) => {
  const r = g.createRadialGradient(w * .42, w * .38, w * .04, w / 2, w / 2, w / 2);
  r.addColorStop(0, 'rgba(250,252,255,1)'); r.addColorStop(.45, 'rgba(206,214,228,.97)');
  r.addColorStop(.8, 'rgba(120,132,156,.85)'); r.addColorStop(1, 'rgba(90,100,124,0)');
  g.fillStyle = r; g.fillRect(0, 0, w, w);
});
// The selection ring round a fighter's base: a bright band with a soft glow either side, tinted by
// its material (selectable green, chosen bone). Flat on the table, like the digital edition's.
const RING = canvasTex(256, 256, (g, w) => {
  const r = g.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2);
  r.addColorStop(0, 'rgba(255,255,255,0)'); r.addColorStop(.6, 'rgba(255,255,255,0)');
  r.addColorStop(.72, 'rgba(255,255,255,.55)'); r.addColorStop(.77, 'rgba(255,255,255,1)');
  r.addColorStop(.82, 'rgba(255,255,255,.55)'); r.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = r; g.fillRect(0, 0, w, w);
});
const RETICLE = canvasTex(256, 256, (g, w) => {
  g.strokeStyle = '#ff5b4e'; g.lineWidth = 14; g.lineCap = 'round';
  g.beginPath(); g.arc(w / 2, w / 2, w * .36, 0, TAU); g.stroke();
  for (let i = 0; i < 4; i++) {
    const a = i * Math.PI / 2, c = Math.cos(a), s = Math.sin(a);
    g.beginPath(); g.moveTo(w / 2 + c * w * .28, w / 2 + s * w * .28); g.lineTo(w / 2 + c * w * .47, w / 2 + s * w * .47); g.stroke();
  }
});

const BLOB_SHADOW_TEX = canvasTex(128, 128, (g, w) => {
  const r = g.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2);
  r.addColorStop(0, 'rgba(0,0,0,0.68)');
  r.addColorStop(0.4, 'rgba(0,0,0,0.36)');
  r.addColorStop(0.8, 'rgba(0,0,0,0.08)');
  r.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = r;
  g.fillRect(0, 0, w, w);
});
const blobShadowGeo = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);

let fontFamily = 'sans-serif';
const fontReady = (async () => {
  try {
    const f = new FontFace('Saira', 'url(../fonts/SairaCondensed-Bold.ttf)', { weight: '700' });
    await f.load();
    document.fonts.add(f);
    fontFamily = 'Saira';
  } catch (e) { /* system font */ }
})();

function heartPath(g, x, y, s) {
  g.beginPath();
  g.moveTo(x + s / 2, y + s * .92);
  g.bezierCurveTo(x - s * .1, y + s * .5, x, y + s * .02, x + s * .27, y + s * .06);
  g.bezierCurveTo(x + s * .4, y + s * .08, x + s * .47, y + s * .18, x + s / 2, y + s * .25);
  g.bezierCurveTo(x + s * .53, y + s * .18, x + s * .6, y + s * .08, x + s * .73, y + s * .06);
  g.bezierCurveTo(x + s, y + s * .02, x + s * 1.1, y + s * .5, x + s / 2, y + s * .92);
  g.closePath();
}

/** The fighter's tag beside its base, as on the digital edition's board: its health in a heart,
    its attack type on a chip edged in the player's colour above it (melee: linked rings; ranged:
    an arrow into a target), and the hero's pieces (Alice's size card, Hellfire, tokens...) stacked
    above that. Everything is right-aligned: the sprite hangs off the base's left side, so it never
    covers the figure. Redrawn when health, attack type, pieces or colour change. */
function drawLabel(p) {
  const c = p.label.material.map.image, g = c.getContext('2d'), W = c.width, H = c.height;
  const k = W / LABEL_W; // canvas density: the layout below is in LABEL_W x LABEL_H units
  g.clearRect(0, 0, W, H);
  const R = W - 4 * k;

  // the heart, health in it (darker when nearly out)
  const hs = 100 * k, hx = R - hs, hy = H - hs - 4 * k;
  g.save();
  g.shadowColor = 'rgba(0,0,0,.6)'; g.shadowBlur = 8 * k; g.shadowOffsetY = 3 * k;
  heartPath(g, hx, hy, hs); g.fillStyle = '#ece6d8'; g.fill();
  g.restore();
  heartPath(g, hx + hs * .07, hy + hs * .075, hs * .86); g.fillStyle = p.hp <= 3 ? '#a3141d' : '#d8323a'; g.fill();
  g.fillStyle = '#fff'; g.font = `800 ${hs * .44}px ${fontFamily}`;
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText(String(p.hp), hx + hs / 2, hy + hs * .5);

  // the attack type chip
  const cw = 86 * k, ch = 40 * k, cx = hx + hs / 2 - cw / 2, cy = hy - ch;
  g.save();
  g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = 6 * k; g.shadowOffsetY = 2 * k;
  g.fillStyle = 'rgba(12,15,21,.92)'; roundRect(g, cx, cy, cw, ch, ch / 2); g.fill();
  g.restore();
  g.lineWidth = 3.5 * k; g.strokeStyle = p.color; roundRect(g, cx, cy, cw, ch, ch / 2); g.stroke();
  attackIcon(g, cx + cw / 2, cy + ch / 2, ch * .7, p.ranged);

  // the hero's pieces above: a card with its name, tokens one by one, or a counter
  const rh = 40 * k;
  let ry = cy - 6 * k;
  for (const it of (p.items || []).slice(0, 2)) {
    ry -= rh;
    const color = it.c || '#ece6d8';
    const many = (it.m ?? it.n ?? 0);
    const tokens = it.k === 'tokens' && many <= 6 ? many : 0;
    const text = it.k === 'card' ? it.t : (tokens ? '' : `${it.t} ${it.m != null ? `${it.n}/${it.m}` : it.n}`);
    g.font = `700 ${rh * .56}px ${fontFamily}`;
    const tw = Math.min(g.measureText(text).width, W - rh * 3);
    const w = rh * 1.1 + (text ? tw + rh * .35 : 0) + tokens * rh * .78 + (tokens ? rh * .2 : 0);
    const x = Math.max(2 * k, R - w);
    g.fillStyle = 'rgba(12,15,21,.92)';
    roundRect(g, x, ry, w, rh, rh * .2); g.fill();
    g.lineWidth = 3 * k; g.strokeStyle = color; g.stroke();
    g.font = `${rh * .62}px "Segoe UI Emoji","Apple Color Emoji","Noto Color Emoji",sans-serif`;
    g.textBaseline = 'middle'; g.textAlign = 'left';
    if (tokens) {
      for (let i = 0; i < tokens; i++) {
        g.globalAlpha = i < (it.n || 0) ? 1 : .25;
        g.fillText(it.e, x + rh * .2 + i * rh * .78, ry + rh * .54);
      }
      g.globalAlpha = 1;
      g.font = `700 ${rh * .5}px ${fontFamily}`; g.fillStyle = color;
      g.fillText(it.t, x + rh * .3 + tokens * rh * .78, ry + rh * .54);
    } else {
      g.fillText(it.e, x + rh * .2, ry + rh * .54);
      g.font = `700 ${rh * .56}px ${fontFamily}`; g.fillStyle = '#fff';
      g.fillText(text, x + rh * 1.1, ry + rh * .56, W - rh * 3);
    }
    ry -= 5 * k;
  }
  g.textAlign = 'left';
  p.label.material.map.needsUpdate = true;
}

/** Attack type icons, in bone on the chip: melee two linked rings with a bar through them,
    ranged an arrow flying into a target. (cx, cy) centre, s size. */
function attackIcon(g, cx, cy, s, ranged) {
  g.save();
  g.strokeStyle = '#ece6d8'; g.fillStyle = '#ece6d8';
  g.lineWidth = s * .13; g.lineCap = 'round'; g.lineJoin = 'round';
  if (!ranged) {
    for (const dx of [-.3, .3]) { g.beginPath(); g.arc(cx + dx * s, cy, s * .3, 0, TAU); g.stroke(); }
    g.beginPath(); g.moveTo(cx - s * .78, cy); g.lineTo(cx + s * .78, cy); g.stroke();
  } else {
    const tx = cx + s * .42;
    g.beginPath(); g.arc(tx, cy, s * .32, 0, TAU); g.stroke();
    g.beginPath(); g.arc(tx, cy, s * .08, 0, TAU); g.fill();
    g.beginPath(); g.moveTo(cx - s * .85, cy); g.lineTo(tx - s * .1, cy); g.stroke();
    g.beginPath(); g.moveTo(tx - s * .06, cy); g.lineTo(tx - s * .3, cy - s * .16); g.lineTo(tx - s * .3, cy + s * .16); g.closePath(); g.fill();
    for (const d of [0, .18]) {
      g.beginPath();
      g.moveTo(cx - s * (.85 - d), cy); g.lineTo(cx - s * (.98 - d), cy - s * .16);
      g.moveTo(cx - s * (.85 - d), cy); g.lineTo(cx - s * (.98 - d), cy + s * .16);
      g.stroke();
    }
  }
  g.restore();
}
function roundRect(g, x, y, w, h, r) {
  g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();
}

/* ---------------------------------------------------------------- figures
   Each fighter is its miniature render (assets/heroes/<hero>/figure*.webp, cut off its printed base
   by tool/make_figures.py) sculpted into a rounded relief: every opaque pixel is raised by how far
   it lies inside the silhouette (a quarter-circle profile, so edges roll over and thin parts stay
   thin), with the render's fine shading pressed in on the front; the back is the same outline with
   only the broad forms. Sidekicks are their round tokens as domed coins. Front and back meet at zero
   thickness on the outline. Every figure turns about its own axis to face the camera. */
let figureIndex = {};       // hero id -> [{file, w, h, baseW, baseX}] (figures.json)
const figuresReady = fetch('figures.json').then(r => (r.ok ? r.json() : {})).then(j => { figureIndex = j || {}; }).catch(() => {});
const figureCache = new Map();  // key -> Promise<{tex, geo}>
const texLoader = new THREE.TextureLoader();

function insideDistance(solid, w, h) {
  const d = new Float32Array(w * h), D2 = Math.SQRT2;
  for (let i = 0; i < d.length; i++) d[i] = solid[i] ? 1e9 : 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x;
    if (!d[i]) continue;
    let v = Math.min(d[i], x > 0 ? d[i - 1] + 1 : 1, y > 0 ? d[i - w] + 1 : 1);
    if (y > 0) v = Math.min(v, x > 0 ? d[i - w - 1] + D2 : D2, x < w - 1 ? d[i - w + 1] + D2 : D2);
    d[i] = v;
  }
  for (let y = h - 1; y >= 0; y--) for (let x = w - 1; x >= 0; x--) {
    const i = y * w + x;
    if (!d[i]) continue;
    let v = Math.min(d[i], x < w - 1 ? d[i + 1] + 1 : 1, y < h - 1 ? d[i + w] + 1 : 1);
    if (y < h - 1) v = Math.min(v, x < w - 1 ? d[i + w + 1] + D2 : D2, x > 0 ? d[i + w - 1] + D2 : D2);
    d[i] = v;
  }
  return d;
}

function boxBlur(src, w, h, r) {
  const tmp = new Float32Array(w * h), out = new Float32Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let s = 0, n = 0;
    for (let k = Math.max(0, x - r); k <= Math.min(w - 1, x + r); k++) { s += src[y * w + k]; n++; }
    tmp[y * w + x] = s / n;
  }
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let s = 0, n = 0;
    for (let k = Math.max(0, y - r); k <= Math.min(h - 1, y + r); k++) { s += tmp[k * w + x]; n++; }
    out[y * w + x] = s / n;
  }
  return out;
}

/** Relief in picture space: x 0..1 across, y 0..1 up, z about ±1. Group 0 is the front, 1 the back. */
function reliefGeometry(img, coin) {
  // detail grid: enough for a figure's folds; a coin is a simple dome (keeps phones at 60 fps)
  const s = Math.min(1, (coin ? tier().coin : tier().grid) / Math.max(img.width, img.height));
  const w = Math.max(8, Math.round(img.width * s)), h = Math.max(8, Math.round(img.height * s));
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.drawImage(img, 0, 0, w, h);
  const px = g.getImageData(0, 0, w, h).data;
  const N = w * h, solid = new Uint8Array(N), lum = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    solid[i] = px[i * 4 + 3] > 128 ? 1 : 0;
    lum[i] = (.299 * px[i * 4] + .587 * px[i * 4 + 1] + .114 * px[i * 4 + 2]) / 255;
  }
  const dist = insideDistance(solid, w, h);
  const R = coin ? Math.max(3, w * .1) : Math.max(4, Math.min(w, h * .6) * .2);
  let z = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    if (!solid[i]) continue;
    const t = Math.min(1, Math.max(0, dist[i] - 1) / R);
    z[i] = Math.sqrt(1 - (1 - t) * (1 - t));
    if (!coin) z[i] *= .6 + .4 * Math.min(1, Math.max(0, dist[i] - 1) / (R * 2.5));
  }
  z = boxBlur(boxBlur(z, w, h, 1), w, h, 1);
  const zb = new Float32Array(z);
  if (!coin) {
    const fine = boxBlur(lum, w, h, 1), soft = boxBlur(lum, w, h, 5), broad = boxBlur(lum, w, h, 10);
    for (let i = 0; i < N; i++) {
      if (!solid[i]) continue;
      const e = Math.min(1, Math.max(0, dist[i] - 1) / R) ** 2;
      z[i] = Math.max(0, z[i] + (fine[i] - soft[i]) * 1.1 * e);
      zb[i] = Math.max(0, zb[i] + (soft[i] - broad[i]) * .8 * e);
    }
  }
  for (let i = 0; i < N; i++) if (!solid[i] || dist[i] <= 1) z[i] = zb[i] = 0;

  // vertices at pixel centres; quads touching any solid pixel (the texture's alpha trims the rest)
  const index = new Int32Array(N).fill(-1), pos = [], uv = [], backZ = [], tris = [];
  const vert = (x, y) => {
    const i = y * w + x;
    if (index[i] < 0) {
      index[i] = pos.length / 3;
      pos.push((x + .5) / w, 1 - (y + .5) / h, z[i]);
      uv.push((x + .5) / w, 1 - (y + .5) / h);
      backZ.push(zb[i]);
    }
    return index[i];
  };
  for (let y = 0; y < h - 1; y++) for (let x = 0; x < w - 1; x++) {
    if (!(solid[y * w + x] || solid[y * w + x + 1] || solid[(y + 1) * w + x] || solid[(y + 1) * w + x + 1])) continue;
    const a = vert(x, y), b = vert(x + 1, y), cc = vert(x, y + 1), d = vert(x + 1, y + 1);
    tris.push(a, cc, b, b, cc, d);
  }
  // back: same outline the other way, wound the other way. A figure keeps the front's UVs; a coin
  // flips them so its portrait reads the right way round from behind.
  const n = pos.length / 3, front = tris.length;
  for (let i = 0; i < n; i++) { pos.push(pos[i * 3], pos[i * 3 + 1], -backZ[i]); uv.push(coin ? 1 - uv[i * 2] : uv[i * 2], uv[i * 2 + 1]); }
  for (let i = 0; i < front; i += 3) tris.push(tris[i] + n, tris[i + 2] + n, tris[i + 1] + n);
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(tris);
  geo.addGroup(0, front, 0);
  geo.addGroup(front, front, 1);
  geo.computeVertexNormals();
  return geo;
}

function loadTex(url) {
  return texLoader.loadAsync(url).then(t => {
    const sharp = sharpened(t.image, tier().figure);
    if (sharp) { t.dispose(); t = new THREE.CanvasTexture(sharp); }
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = tierAniso(8);
    t.userData.shared = true; // cached across pieces: never disposed with one
    return t;
  });
}

/* The miniature renders are small (about 250-450 px), so up close the GPU stretches them into a
   blur and their cut-out edge into stairs. On the higher tiers each one is upscaled once with the
   browser's best resampling, then given a light unsharp mask on its colour (weighted by alpha,
   so the transparent surround doesn't bleed a dark halo in). The smooth upscaled alpha also
   gives the alpha test, and alpha-to-coverage, a clean outline to cut along. */
function sharpened(img, target) {
  const long = Math.max(img.width, img.height);
  if (!target || !long || long * 1.15 >= target) return null;
  const s = target / long, w = Math.round(img.width * s), h = Math.round(img.height * s);
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.imageSmoothingEnabled = true;
  g.imageSmoothingQuality = 'high';
  g.drawImage(img, 0, 0, w, h);
  const im = g.getImageData(0, 0, w, h), px = im.data, N = w * h;
  const a = new Float32Array(N), ch = [new Float32Array(N), new Float32Array(N), new Float32Array(N)];
  for (let i = 0; i < N; i++) {
    const al = px[i * 4 + 3] / 255;
    a[i] = al;
    for (let k = 0; k < 3; k++) ch[k][i] = px[i * 4 + k] * al;
  }
  const r = Math.max(1, Math.round(s * .9)), amount = .55;
  const ba = blurFast(a, w, h, r), bc = ch.map(x => blurFast(x, w, h, r));
  for (let i = 0; i < N; i++) {
    if (a[i] <= 0 || ba[i] <= 1e-3) continue;
    for (let k = 0; k < 3; k++) {
      const v = px[i * 4 + k], soft = bc[k][i] / ba[i];
      px[i * 4 + k] = clamp(Math.round(v + (v - soft) * amount), 0, 255);
    }
  }
  g.putImageData(im, 0, 0);
  return c;
}

/** Two passes of a running-sum box blur (close to a Gaussian), O(pixels) whatever the radius. */
function blurFast(src, w, h, r) {
  let a = src, b = new Float32Array(w * h);
  for (let pass = 0; pass < 2; pass++) {
    for (let y = 0; y < h; y++) {
      const o = y * w;
      let sum = 0;
      for (let x = -r; x <= r; x++) sum += a[o + clamp(x, 0, w - 1)];
      for (let x = 0; x < w; x++) {
        b[o + x] = sum / (2 * r + 1);
        sum += a[o + Math.min(w - 1, x + r + 1)] - a[o + Math.max(0, x - r)];
      }
    }
    const t = new Float32Array(w * h);
    for (let x = 0; x < w; x++) {
      let sum = 0;
      for (let y = -r; y <= r; y++) sum += b[clamp(y, 0, h - 1) * w + x];
      for (let y = 0; y < h; y++) {
        t[y * w + x] = sum / (2 * r + 1);
        sum += b[Math.min(h - 1, y + r + 1) * w + x] - b[Math.max(0, y - r) * w + x];
      }
    }
    a = t;
  }
  return a;
}

function loadFigure(url, coin) {
  if (!figureCache.has(url)) figureCache.set(url, loadTex(url).then(tex => ({ tex, geo: reliefGeometry(tex.image, coin) })));
  return figureCache.get(url);
}

const podiumGeo = (() => {
  const pts = [[0, 0], [1, 0], [1, .72], [.985, .9], [.95, 1], [0, 1]].map(([x, y]) => new THREE.Vector2(x, y));
  return new THREE.LatheGeometry(pts, 48);
})();
const PODIUM_H = .06;

/** Swaps the orb for the fighter's figure once its pictures load (the orb stays if they don't). */
async function buildFigure(p, f) {
  await figuresReady;
  const hero = f.mini && figureIndex[f.mini];
  let spec, coin = false;
  if (f.hero && hero && hero.length) spec = hero[Math.min(f.v || 0, hero.length - 1)];
  else if (!f.hero && f.mini && f.fid) { spec = { file: `../heroes/${f.mini}/${f.fid}.webp` }; coin = true; }
  if (!spec) return;
  let fig;
  try { fig = await loadFigure(spec.file, coin); } catch (e) { return; }
  if (!pieces.has(p.id) || pieces.get(p.id) !== p) return;   // gone while loading

  // the same size as the Map Viewer: a hero's podium is .72 of a space across, a sidekick's .54
  const r = p.hero ? .36 : (p.rad < .15 ? .2 : .27), h = PODIUM_H;
  const podium = new THREE.Mesh(podiumGeo, new THREE.MeshStandardMaterial({ color: new THREE.Color(p.color), roughness: .45, metalness: .05 }));
  podium.scale.set(r, h, r);
  podium.userData.casts = true;
  const cap = new THREE.Mesh(new THREE.CircleGeometry(r * .95, 40).rotateX(-Math.PI / 2),
    new THREE.MeshStandardMaterial({ color: new THREE.Color(p.color).multiplyScalar(.6), roughness: .8 }));
  cap.position.y = h + .001;

  // a render's printed base is as wide as the podium, which keeps each figure's real proportions;
  // a token stands a little wider than its podium
  let sw, sh, bx = .5;
  if (coin) { sw = sh = 2 * r * 1.12; } else {
    const k = 2 * r * .98 / spec.baseW;
    sw = spec.w * k; sh = spec.h * k;
    const tallest = 2.6 * 2 * r;
    if (sh > tallest) { sw *= tallest / sh; sh = tallest; }
    bx = spec.baseX / spec.w;
  }
  const depth = (coin ? .05 : .18) * 2 * r;
  const geo = fig.geo.clone();
  geo.scale(sw, sh, depth);
  geo.translate(-bx * sw, coin ? .004 : -.004, 0);
  // alpha-to-coverage turns the cut-out's hard alpha-test edge into a multisampled, smooth one
  const body = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: fig.tex, alphaTest: .5, alphaToCoverage: G.aa, roughness: .62 }));
  body.position.y = h;
  body.userData.casts = true;
  // turned toward the camera every frame (faceCamera)
  const pivot = new THREE.Group();
  pivot.add(body);
  const fig3 = new THREE.Group();
  fig3.add(podium, cap, pivot);
  fig3.traverse(o => { if (o.isMesh) { o.castShadow = G.shadows > 0 && !!o.userData.casts; o.receiveShadow = G.shadows > 0; } });
  p.group.add(fig3);
  p.figure = fig3;
  p.pivot = pivot;
  p.podium = podium;
  p.cap = cap;

  // the orb becomes the figure's centre: taps, effects and the reticle aim at it
  p.orb.visible = false;
  p.orb.position.y = h + sh * .5;
  p.hitR = Math.max(r * 1.2, sh * .55);
  p.reticle.position.y = p.orb.position.y;
  p.glow.position.y = .05;
  p.glow.scale.setScalar(r * 3.2);
  p.tagGap = r * 1.02;
  renderer.shadowMap.needsUpdate = true;
  invalidate(3);
}

/** Figures turn about their own upright axis to face the camera (tags are sprites and already do).
    Tags grow as the camera comes closer, up to a cap, so a duel's close-up stays on the fighters;
    each keeps clear of its base's left edge. */
function faceCamera() {
  const near = span * .42, far = span;
  for (const p of pieces.values()) {
    const g = p.group.position, d = camera.position.distanceTo(g);
    // up close: no bigger on screen than at `near`; far off: no smaller than at `far`
    const k = d < near ? d / near : d > far ? d / far : 1, ls = p.label.userData.ls * k;
    p.label.scale.set(ls, ls * LABEL_H / LABEL_W, 1);
    p.label.center.x = 1 + p.tagGap / ls;
    if (!p.pivot) continue;
    p.pivot.rotation.y = Math.atan2(camera.position.x - g.x, camera.position.z - g.z);
  }
}

/* ---------------------------------------------------------------- pieces */
const pieces = new Map();   // fighter uid -> piece
const orbGeo = new THREE.SphereGeometry(1, 32, 20);
const baseGeo = new THREE.RingGeometry(.74, 1, 40).rotateX(-Math.PI / 2);
// the ring's bright band sits at radius 1 (the texture's band is at .77 of its half-width)
const ringGeo = new THREE.PlaneGeometry(2.6, 2.6).rotateX(-Math.PI / 2);
const basic = (color, opacity = 1) => new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false, toneMapped: false });

function makePiece(f) {
  const rad = f.hero ? .23 : (f.small ? .11 : .165);
  const color = new THREE.Color(f.color);
  const group = new THREE.Group();
  const orb = new THREE.Mesh(orbGeo, new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: .5, roughness: .25, metalness: .05 }));
  orb.scale.setScalar(rad);
  orb.position.y = rad + .14;
  orb.userData.casts = true;
  orb.castShadow = G.shadows > 0;
  orb.userData.fid = f.id;
  const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: GLOW, color, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: .55, toneMapped: false }));
  glow.position.y = orb.position.y;
  glow.scale.setScalar(rad * 5.2);
  const base = new THREE.Mesh(baseGeo, basic(color, .9));
  base.scale.setScalar(rad * 1.45);
  base.position.y = .006;
  const blobShadow = new THREE.Mesh(blobShadowGeo, new THREE.MeshBasicMaterial({ map: BLOB_SHADOW_TEX, transparent: true, opacity: .78, depthWrite: false, toneMapped: false }));
  blobShadow.scale.setScalar(rad * 3.4);
  blobShadow.position.y = .003;
  blobShadow.renderOrder = 1;
  blobShadow.visible = G.shadows === 0;
  const ring = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ map: RING, color: SELECT, transparent: true, depthWrite: false, toneMapped: false }));
  ring.scale.setScalar(rad * 1.9);
  ring.position.y = .068;
  ring.renderOrder = 3;
  ring.visible = false;
  const fakeGlow = new THREE.Sprite(new THREE.SpriteMaterial({ map: GLOW, color: SELECT, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: .65, toneMapped: false }));
  fakeGlow.position.y = .069;
  fakeGlow.scale.setScalar(rad * 3.4);
  fakeGlow.renderOrder = 2;
  fakeGlow.visible = false;
  const reticle = new THREE.Sprite(new THREE.SpriteMaterial({ map: RETICLE, depthTest: false, transparent: true, toneMapped: false }));
  reticle.position.y = orb.position.y;
  reticle.scale.setScalar(rad * 4.2);
  reticle.renderOrder = 9;
  reticle.visible = false;
  // the badge canvas is as dense as the tier and screen call for, so it stays crisp up close
  const lk = clamp(tier().label * Math.min(DPR(), 2) / 2, 1, 2.5);
  const lc = document.createElement('canvas'); lc.width = Math.round(LABEL_W * lk); lc.height = Math.round(LABEL_H * lk);
  const lt = new THREE.CanvasTexture(lc); lt.colorSpace = THREE.SRGBColorSpace;
  lt.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
  const label = new THREE.Sprite(new THREE.SpriteMaterial({ map: lt, depthTest: false, transparent: true, toneMapped: false }));
  label.userData.base = f.hero ? 1 : (f.small ? .62 : .8);
  label.center.set(1, 0);
  label.position.y = .02;
  label.renderOrder = 10;
  label.userData.fid = f.id;
  group.add(base, blobShadow, ring, fakeGlow, orb, glow, reticle, label);
  scene.add(group);
  const p = { id: f.id, group, orb, glow, base, ring, fakeGlow, blobShadow, reticle, label, rad, hitR: rad * 1.5, color: f.color, name: f.name, hp: f.hp, hero: f.hero, ranged: !!f.ranged, space: f.space, anim: null, items: f.items || [], itemsKey: JSON.stringify(f.items || []) };
  // the tag hangs off the left of the base (the orb's ring until the figure's podium arrives)
  p.tagGap = rad * 1.5;
  sizePiece(p);
  drawLabel(p);
  fontReady.then(() => { drawLabel(p); invalidate(); });
  buildFigure(p, f);
  return p;
}

const LABEL_W = 230, LABEL_H = 340;

/** Tag size and orb glow follow the graphics settings. */
function sizePiece(p) {
  const ls = p.label.userData.ls = p.label.userData.base * G.labels * .6;
  p.label.scale.set(ls, ls * LABEL_H / LABEL_W, 1);
  p.orb.material.emissiveIntensity = fxOn().bloom ? 1.25 : .5;
}

function disposePiece(p) {
  scene.remove(p.group);
  if (p.tail) {
    // the back-space knob shares the orb's sphere; its bar and both materials are its own
    scene.remove(p.tail);
    p.tail.traverse(o => {
      if (o.geometry && o.geometry !== orbGeo) o.geometry.dispose();
      if (o.material) o.material.dispose();
    });
  }
  p.group.traverse(o => {
    if (p.figure && o.geometry && o.geometry !== podiumGeo && o.parent && o.parent !== p.group) o.geometry.dispose();
    for (const m of [].concat(o.material || [])) {
      if (m.map && m.map !== GLOW && m.map !== RETICLE && m.map !== RING && !m.map.userData.shared) m.map.dispose();
      m.dispose();
    }
  });
}

function placePiece(p) {
  const s = spaces.get(p.space);
  // Small fighters sharing a space fan out around its centre ([x, y] in space radii).
  const [ox, oy] = p.off || [0, 0];
  if (s) p.group.position.set(s.x + ox * SLOT, s.top, s.z + oy * SLOT);
}
const SLOT = .36;

/** A large fighter in two spaces (T. Rex): a smaller orb on the back space, joined by a bar. */
function placeTail(p) {
  const t = p.tailSpace != null && !p.anim ? spaces.get(p.tailSpace) : null;
  if (!t) { if (p.tail) p.tail.visible = false; return; }
  if (!p.tail) {
    const color = new THREE.Color(p.color);
    p.tail = new THREE.Group();
    const knob = new THREE.Mesh(orbGeo, new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: .35, roughness: .35 }));
    knob.scale.setScalar(p.rad * .6);
    knob.position.y = p.rad * .6 + .08;
    const bar = new THREE.Mesh(new THREE.CylinderGeometry(.06, .06, 1, 10), basic(color, .6));
    bar.name = 'bar';
    p.tail.add(knob, bar);
    scene.add(p.tail);
  }
  const head = spaces.get(p.space);
  p.tail.visible = true;
  p.tail.position.set(t.x, t.top, t.z);
  const bar = p.tail.getObjectByName('bar');
  const dx = head.x - t.x, dz = head.z - t.z, len = Math.hypot(dx, dz);
  bar.scale.set(1, len, 1);
  bar.position.set(dx / 2, .18, dz / 2);
  bar.rotation.set(0, 0, 0);
  bar.lookAt(new V3(t.x + dx, t.top + .18, t.z + dz));
  bar.rotateX(Math.PI / 2);
}

/* ---------------------------------------------------------------- marks & tokens */
const markGroup = new THREE.Group();
const tokenGroup = new THREE.Group();
let marks = {}, focus = new Set(), pulsing = false;
const spaceFill = new THREE.CircleGeometry(.36, 40).rotateX(-Math.PI / 2);
const spaceRing = new THREE.RingGeometry(.38, .47, 48).rotateX(-Math.PI / 2);
const pendRing = new THREE.RingGeometry(.44, .56, 48).rotateX(-Math.PI / 2);
const pulseMats = [];

function tube(points, radius, color, opacity = 1) {
  const path = new THREE.CurvePath();
  for (let i = 1; i < points.length; i++) path.add(new THREE.LineCurve3(points[i - 1], points[i]));
  return new THREE.Mesh(new THREE.TubeGeometry(path, Math.max(1, points.length - 1) * 4, radius, 8, false), basic(color, opacity));
}
const at = (id, lift = 0) => { const s = spaces.get(id); return new V3(s.x, s.top + lift, s.z); };

function clearGroup(g) {
  for (const o of [...g.children]) {
    g.remove(o);
    o.traverse(c => {
      if (c.geometry && ![spaceFill, spaceRing, pendRing, orbGeo, baseGeo, ringGeo].includes(c.geometry)) c.geometry.dispose();
      if (c.material) c.material.dispose();
    });
  }
}

function buildMarks(m) {
  clearGroup(markGroup);
  pulseMats.length = 0;
  const color = m.harmful ? TARGET : SELECT;
  for (const id of m.spaces || []) {
    if (!spaces.has(id)) continue;
    const fill = new THREE.Mesh(spaceFill, basic(color, .3));
    const ring = new THREE.Mesh(spaceRing, basic(color, .9));
    fill.position.copy(at(id, .004)); ring.position.copy(at(id, .005));
    // over the fog puffs (4): a cloud never hides that its space can be picked
    fill.renderOrder = ring.renderOrder = 5;
    pulseMats.push(fill.material);
    markGroup.add(fill, ring);
  }
  if (m.pendingSpace != null && spaces.has(m.pendingSpace)) {
    const r = new THREE.Mesh(pendRing, basic(BONE));
    r.position.copy(at(m.pendingSpace, .006)); r.renderOrder = 6;
    markGroup.add(r);
  }
  // the token being moved (Invisible Man's fog): a bone ring where it is now
  if (m.subjectSpace != null && spaces.has(m.subjectSpace)) {
    const r = new THREE.Mesh(pendRing, basic(BONE, .75));
    r.position.copy(at(m.subjectSpace, .007)); r.scale.setScalar(1.12); r.renderOrder = 6;
    markGroup.add(r);
  }
  if (m.preview && m.preview.length > 1) {
    const pts = m.preview.filter(id => spaces.has(id)).map(id => at(id, .05));
    if (pts.length > 1) {
      markGroup.add(tube(pts, .06, 0x000000, .45));
      markGroup.add(tube(pts, .035, BONE));
    }
  }
  for (const [a, b] of m.edges || []) {
    if (!spaces.has(a) || !spaces.has(b)) continue;
    const pend = m.pendingEdge && m.pendingEdge[0] === a && m.pendingEdge[1] === b;
    const t = tube([at(a, .04), at(b, .04)], pend ? .07 : .05, pend ? BONE : SELECT, pend ? 1 : .8);
    if (!pend) pulseMats.push(t.material);
    markGroup.add(t);
  }
  pulsing = pulseMats.length > 0 || (m.select || []).length > 0 || (m.targets || []).length > 0;
}

let fogSpots = [];  // [{space, at: V3}]: where a tap on a cloud picks its space

function buildTokens(tokens) {
  clearGroup(tokenGroup);
  fogSpots = [];
  const shadowCount = {}, insightCount = {};
  const pickable = new Set(marks.spaces || []);
  for (const t of tokens || []) {
    if (t.kind === 'fog' && spaces.has(t.space)) {
      // Invisible Man's fog: a bank of cloud puffs over a soft grey shadow on the space. A cloud
      // that can be picked (or the one being moved) is tinted the choice's colour.
      const c = at(t.space, 0);
      const tint = marks.subjectSpace === t.space ? '#fff4dc' : pickable.has(t.space) ? (marks.harmful ? '#ffc2ba' : '#d4f7b4') : '#ffffff';
      const shade = new THREE.Mesh(spaceFill, basic('#5a6478', .45));
      shade.position.set(c.x, c.y + .004, c.z);
      shade.scale.setScalar(1.25);
      tokenGroup.add(shade);
      fogSpots.push({ space: t.space, at: new V3(c.x, c.y + .28, c.z) });
      for (const [dx, dy, dz, s] of [[-.2, .2, .06, .5], [.2, .22, .1, .48], [0, .3, -.14, .56], [.04, .18, .2, .44], [-.06, .42, 0, .46], [.16, .38, -.06, .4]]) {
        const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: PUFF, color: tint, transparent: true, depthWrite: false, opacity: .96 }));
        sp.position.set(c.x + dx, c.y + dy, c.z + dz);
        sp.scale.setScalar(s);
        sp.renderOrder = 4;
        tokenGroup.add(sp);
      }
    } else if (t.kind === 'trap' && spaces.has(t.space)) {
      // Muldoon's traps: a dark steel ring with an orange rim, at the space's edge.
      const c = at(t.space, .02);
      const ring = new THREE.Mesh(new THREE.TorusGeometry(.11, .035, 8, 20).rotateX(Math.PI / 2), new THREE.MeshStandardMaterial({ color: '#3a3a3a', metalness: .7, roughness: .35, emissive: '#f08a3c', emissiveIntensity: .35 }));
      ring.position.set(c.x + .24, c.y + .03, c.z + .24);
      tokenGroup.add(ring);
    } else if (t.kind === 'insight' && spaces.has(t.space)) {
      // Dr. Sattler's insight tokens: small amber gems, offset so several can share a space.
      const n = (insightCount[t.space] = (insightCount[t.space] || 0) + 1) - 1;
      const c = at(t.space, .02);
      const gem = new THREE.Mesh(new THREE.OctahedronGeometry(.07, 0), new THREE.MeshStandardMaterial({ color: '#f2c14e', roughness: .3, emissive: '#f2c14e', emissiveIntensity: .4 }));
      gem.position.set(c.x - .26 + n * .12, c.y + .07, c.z - .26);
      tokenGroup.add(gem);
    } else if (t.kind === 'shadow' && spaces.has(t.space)) {
      // Spike's shadow tokens: dark discs with a violet rim, offset so several can share a space.
      const n = (shadowCount[t.space] = (shadowCount[t.space] || 0) + 1) - 1;
      const c = at(t.space, .02);
      const disc = new THREE.Mesh(new THREE.CylinderGeometry(.13, .13, .03, 24), new THREE.MeshStandardMaterial({ color: '#1a0f24', roughness: .6, emissive: '#b04be0', emissiveIntensity: .35 }));
      disc.position.set(c.x - .22 + n * .14, c.y + .015 + n * .03, c.z + .22);
      tokenGroup.add(disc);
    } else if (t.a != null && spaces.has(t.a) && spaces.has(t.b)) {
      const m = at(t.a).lerp(at(t.b), .5);
      const d = new THREE.Mesh(new THREE.OctahedronGeometry(.15, 0), new THREE.MeshStandardMaterial({ color: '#1c1c1c', roughness: .5, emissive: '#c8352c', emissiveIntensity: .25 }));
      d.scale.y = .45;
      d.position.set(m.x, m.y + .08, m.z);
      d.userData.casts = true;
      d.castShadow = G.shadows > 0;
      tokenGroup.add(d);
    }
  }
}

/* ---------------------------------------------------------------- state */
function applyState(s) {
  if (!Array.isArray(s.fighters)) return; // not a board state
  if (!loaded) { pendingState = s; return; }
  pendingState = null;
  const seen = new Set();
  for (const f of s.fighters) {
    seen.add(f.id);
    let p = pieces.get(f.id);
    if (!p) { p = makePiece(f); pieces.set(f.id, p); }
    const items = JSON.stringify(f.items || []);
    if (p.hp !== f.hp || p.name !== f.name || p.color !== f.color || p.itemsKey !== items || p.ranged !== !!f.ranged) {
      p.itemsKey = items;
      p.items = f.items || [];
      p.ranged = !!f.ranged;
      const recolor = p.color !== f.color;
      p.hp = f.hp; p.name = f.name; p.color = f.color;
      if (recolor) {
        const c = new THREE.Color(f.color);
        p.orb.material.color.copy(c); p.orb.material.emissive.copy(c); p.glow.material.color.copy(c); p.base.material.color.copy(c);
        if (p.podium) { p.podium.material.color.copy(c); p.cap.material.color.copy(c).multiplyScalar(.6); }
      }
      drawLabel(p);
    }
    p.space = f.space;
    p.off = f.off;
    p.tailSpace = f.tail;
    if (!p.anim) placePiece(p);
    placeTail(p);
  }
  for (const [id, p] of pieces) if (!seen.has(id)) { disposePiece(p); pieces.delete(id); }
  marks = s.marks || {};
  focus = new Set(s.focus || []);
  const sel = new Set(marks.select || []), tgt = new Set(marks.targets || []);
  for (const p of pieces.values()) {
    const pend = marks.pendingFighter === p.id, subj = marks.subject === p.id;
    p.ring.visible = sel.has(p.id) || pend || subj;
    p.ring.material.color.setHex(pend || subj ? BONE : SELECT);
    if (p.fakeGlow) {
      p.fakeGlow.visible = p.ring.visible && !fxOn().bloom;
      p.fakeGlow.material.color.copy(p.ring.material.color);
    }
    p.ring.userData.pulse = sel.has(p.id) && !pend;
    p.reticle.visible = tgt.has(p.id);
    p.glow.material.opacity = focus.has(p.id) ? .95 : .55;
    p.glow.scale.setScalar(p.rad * (focus.has(p.id) ? 6.5 : 5.2));
  }
  buildMarks(marks);
  buildTokens(s.tokens);
  renderer.shadowMap.needsUpdate = true;
  invalidate();
}

function startMove(id, path, ms) {
  const p = pieces.get(id);
  if (!p || !path || path.length < 2 || !(ms > 0)) return;
  p.anim = { path: path.filter(s => spaces.has(s)), start: performance.now(), ms };
  p.space = path[path.length - 1];
}

/* ---------------------------------------------------------------- effects */
const fxList = [];
function burst(id, text, color, sparks, ms) {
  const p = pieces.get(id);
  if (!p) return;
  const origin = p.group.position.clone().add(new V3(0, p.orb.position.y, 0));
  const tk = Math.round(clamp(tier().label * Math.min(DPR(), 2) / 2, 1, 2.5) * 2) / 2;
  const tex = canvasTex(256 * tk, 128 * tk, (g, w, h) => {
    g.font = `800 ${h * .8}px ${fontFamily}`;
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.lineWidth = h * .1; g.strokeStyle = 'rgba(0,0,0,.85)'; g.strokeText(text, w / 2, h / 2);
    g.fillStyle = color; g.fillText(text, w / 2, h / 2);
  });
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, transparent: true, toneMapped: false }));
  sprite.scale.set(.9, .45, 1);
  sprite.renderOrder = 11;
  scene.add(sprite);
  let points = null, vel = null;
  if (sparks) {
    const n = 26, pos = new Float32Array(n * 3);
    vel = [];
    for (let i = 0; i < n; i++) {
      pos.set([origin.x, origin.y, origin.z], i * 3);
      const a = Math.random() * TAU, up = Math.random() * 1.6 + .4, sp = Math.random() * 1.6 + .6;
      vel.push(new V3(Math.cos(a) * sp, up, Math.sin(a) * sp));
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    points = new THREE.Points(g, new THREE.PointsMaterial({ color, size: .07, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false }));
    scene.add(points);
  }
  fxList.push({ sprite, points, vel, origin, start: performance.now(), ms: Math.max(300, ms || 800) });
}

/* ---------------------------------------------------------------- picking */
const raycaster = new THREE.Raycaster();
function tap(cx, cy) {
  if (!loaded) return;
  const ndc = new THREE.Vector2(cx / innerWidth * 2 - 1, -(cy / innerHeight) * 2 + 1);
  raycaster.setFromCamera(ndc, camera);
  // Fighters first: a sphere round the figure (or orb), a little bigger for fingers. Badges don't
  // count: they float over the neighbouring spaces.
  let best = null, bestD = Infinity;
  const sphere = new THREE.Sphere();
  for (const p of pieces.values()) {
    sphere.set(p.group.position.clone().add(new V3(0, p.orb.position.y, 0)), p.hitR);
    const at = raycaster.ray.intersectSphere(sphere, new V3());
    const d = at && at.distanceTo(raycaster.ray.origin);
    if (d != null && d < bestD) { bestD = d; best = p; }
  }
  // A fog cloud floats over its space: a tap on the cloud picks that space (nearer than a fighter
  // hit behind it), wherever the ray meets the table.
  let cloud = null;
  for (const f of fogSpots) {
    sphere.set(f.at, .42);
    const hit = raycaster.ray.intersectSphere(sphere, new V3());
    const d = hit && hit.distanceTo(raycaster.ray.origin);
    if (d != null && d < bestD) { bestD = d; cloud = f; }
  }
  if (cloud) { const s = spaces.get(cloud.space); post({ t: 'tap', x: s.x, y: s.z }); return; }
  // The piece's own position (not its space's centre), so a tap picks between fighters sharing a space.
  if (best && spaces.has(best.space)) { post({ t: 'tap', x: best.group.position.x, y: best.group.position.z }); return; }
  // Otherwise the nearest point on the board's surface (bridges are a little higher).
  const plane = new THREE.Plane(new V3(0, 1, 0), -.02);
  const pt = raycaster.ray.intersectPlane(plane, new V3());
  if (pt) post({ t: 'tap', x: pt.x, y: pt.z });
}

/* ---------------------------------------------------------------- frame loop */
const FRAME_MS = 1000 / 60;
let nextFrame = 0, lastRender = 0, lastStep = 0, frameNo = 0;

function loop(now) {
  // Frame pacing: at most 60 frames a second (a 90/120/144 Hz screen would otherwise draw two or
  // more frames per one that's needed, halving the headroom). Ultra is left uncapped.
  if (G.tier < 3 && now < nextFrame - 2) {
    if (!document.hidden) loopId = requestAnimationFrame(loop);
    return;
  }
  let busy = false, motion = dirty > 0, moving = false;

  if (camTween) {
    const t = clamp((now - camTween.start) / camTween.ms, 0, 1), k = ease(t), a = camTween.from, b = camTween.to;
    rig.target.lerpVectors(a.target, b.target, k);
    rig.r = a.r * Math.pow(b.r / a.r, k); // log space: a push-in closes in at an even pace
    rig.phi = a.phi + (b.phi - a.phi) * k;
    rig.theta = a.theta + (b.theta - a.theta) * k;
    syncCamera();
    goalToRig();
    if (t >= 1) camTween = null;
    busy = motion = true;
  }
  const dt = clamp((now - lastStep) / 1000, 0, .05);
  lastStep = now;
  if (stepCamera(dt)) busy = motion = true;

  for (const p of pieces.values()) {
    const a = p.anim;
    if (!a) continue;
    busy = motion = moving = true;
    const segs = a.path.length - 1;
    const x = clamp((now - a.start) / a.ms, 0, 1) * segs;
    const i = Math.min(Math.floor(x), segs - 1), u = ease(x - i);
    const A = spaces.get(a.path[i]), B = spaces.get(a.path[i + 1]);
    p.group.position.set(A.x + (B.x - A.x) * u, A.top + (B.top - A.top) * u + Math.sin(Math.PI * u) * .28, A.z + (B.z - A.z) * u);
    if (x >= segs) { p.anim = null; placePiece(p); renderer.shadowMap.needsUpdate = true; }
  }

  if (pulsing) {
    busy = true;
    const ph = .5 - .5 * Math.cos(now / 900 * TAU);
    for (const m of pulseMats) m.opacity = .22 + .3 * ph;
    for (const p of pieces.values()) {
      if (p.ring.visible) {
        const s = p.rad * (p.ring.userData.pulse ? 1.85 + .2 * ph : 1.9);
        p.ring.scale.setScalar(s);
        if (p.fakeGlow) p.fakeGlow.scale.setScalar(s * 1.8);
      }
      if (p.reticle.visible) p.reticle.scale.setScalar(p.rad * (4 + .5 * ph));
    }
  }
  if (focus.size) {
    busy = true;
    const ph = .5 - .5 * Math.cos(now / 600 * TAU);
    for (const id of focus) { const p = pieces.get(id); if (p) p.glow.material.opacity = .75 + .25 * ph; }
  }

  for (let i = fxList.length - 1; i >= 0; i--) {
    const f = fxList[i], t = clamp((now - f.start) / f.ms, 0, 1);
    busy = motion = true;
    const rise = (1 - Math.pow(1 - t, 3)) * .7;
    f.sprite.position.copy(f.origin).add(new V3(0, .35 + rise, 0));
    f.sprite.material.opacity = t < .7 ? 1 : (1 - t) / .3;
    if (f.points) {
      const pos = f.points.geometry.attributes.position, dt = t * f.ms / 1000;
      for (let j = 0; j < f.vel.length; j++) {
        const v = f.vel[j];
        pos.setXYZ(j, f.origin.x + v.x * dt * .6, f.origin.y + v.y * dt * .6 - 1.4 * dt * dt, f.origin.z + v.z * dt * .6);
      }
      pos.needsUpdate = true;
      f.points.material.opacity = 1 - t;
    }
    if (t >= 1) {
      scene.remove(f.sprite); f.sprite.material.map.dispose(); f.sprite.material.dispose();
      if (f.points) { scene.remove(f.points); f.points.geometry.dispose(); f.points.material.dispose(); }
      fxList.splice(i, 1);
    }
  }

  let shake = null;
  if (now < shakeUntil) {
    busy = motion = true;
    const k = (shakeUntil - now) / 320;
    shake = new V3(Math.sin(now * .09) * .06 * k, 0, Math.cos(now * .11) * .04 * k);
    camera.position.add(shake);
  }

  // Only highlights breathing: on the lower tiers that's redrawn at a lower rate (it's a slow pulse),
  // which leaves the GPU, and a phone's battery, room for the frames that matter.
  const idleMs = 1000 / tier().idleFps;
  const idle = busy && !motion && now - lastRender < idleMs - 2;
  const draw = (busy || dirty > 0) && !idle;
  govern(now, draw, motion || idleMs <= FRAME_MS + 1);
  if (draw) {
    faceCamera();
    // Pieces moving: their shadows follow every frame, or every other one once the governor is
    // saving time.
    if (moving && (!(G.auto && gov.level >= 3) || (frameNo & 1) === 0)) renderer.shadowMap.needsUpdate = true;
    if (composer) composer.render(); else renderer.render(scene, camera);
    fpsFrames++;
    frameNo++;
    lastRender = now;
    nextFrame = now - nextFrame > FRAME_MS ? now + FRAME_MS : nextFrame + FRAME_MS;
    if (dirty > 0) dirty--;
    if (busy) dirty = Math.max(dirty, 1);
  }
  if (shake) camera.position.sub(shake);
  if (G.fps && now - fpsStart >= 1000) {
    post({ t: 'fps', v: Math.round(fpsFrames * 1000 / (now - fpsStart)) });
    fpsFrames = 0; fpsStart = now;
  }
  if (draw) stepWarmupBench(now - (lastStep || now));

  const anyMoving = Array.from(pieces.values()).some(p => p.anim != null);
  const stillActive = (camTween != null) || fling.lengthSq() > 0 || fxList.length > 0 ||
                      (now < shakeUntil) || (dirty > 0) || pulsing || anyMoving;
  if (!document.hidden && stillActive) {
    loopId = requestAnimationFrame(loop);
  } else {
    pauseLoop();
  }
}
let fpsFrames = 0, fpsStart = 0;

/* Frame-time governor: holds 60 fps by stepping down a ladder while frames run long, cheapest
   loss first, and climbing back once they've been on time for a while:
     level 0 full resolution, 1 90%, 2 ambient occlusion off, 3 80% (moving shadows at half rate),
     4 bloom off, 5 70%, 6 60%.
   Steps that change nothing with the current settings are skipped. It measures only frames drawn
   back to back (every animation tick drew one: a slow device's long frames count, an idle pause
   doesn't), over half a second or 30 frames. If the whole ladder buys nothing (the screen or a
   battery saver caps the rate, or the frame is CPU-bound) it goes back to full quality and
   holds for a minute rather than blur the picture for no gain. A step back up that soon runs
   slow again doubles the wait before the next try, so it settles instead of see-sawing. */
const RES_STEP = [1, .9, .9, .8, .8, .7, .6];
const GOV_NO_AO = 2, GOV_NO_BLOOM = 4, GOV_MAX = RES_STEP.length - 1;
const SLOW_MS = 18.5, ON_TIME_MS = 17.6; // ~54 fps and ~57 fps
const gov = { level: 0, last: 0, chain: false, sum: 0, n: 0, goodSince: 0, wait: 3000, fullAvg: 0, raisedAt: 0, holdUntil: 0 };
const govRes = () => (G.auto ? gov.level : 0);
const govConfig = l => `${RES_STEP[l]}|${G.ao && l < GOV_NO_AO}|${G.bloom && l < GOV_NO_BLOOM}`;

/** Called on every animation tick: `drew` whether it rendered, `sample` whether it counts. */
function govern(now, drew, sample) {
  const dt = now - gov.last, chained = gov.chain;
  gov.last = now;
  gov.chain = drew && sample;
  if (!G.auto || !drew || !sample || !chained || dt <= 0 || !loaded) return;
  gov.sum += dt; gov.n++;
  if (gov.n < 30 && !(gov.sum >= 500 && gov.n >= 3)) return;
  const avg = gov.sum / gov.n;
  gov.sum = gov.n = 0;
  if (avg > SLOW_MS) {
    gov.goodSince = 0;
    if (gov.level === 0) gov.fullAvg = avg;
    if (gov.level === GOV_MAX && avg > gov.fullAvg * .9) {
      setGovLevel(0);
      gov.holdUntil = now + 60000;
    } else if (gov.level < GOV_MAX && now >= gov.holdUntil) {
      if (now - gov.raisedAt < 4000) gov.wait = Math.min(60000, gov.wait * 2);
      setGovLevel(nextGovLevel(1));
    }
  } else if (avg < ON_TIME_MS) {
    if (!gov.goodSince) gov.goodSince = now;
    else if (gov.level > 0 && now - gov.goodSince > gov.wait) {
      setGovLevel(nextGovLevel(-1));
      gov.raisedAt = now;
      gov.goodSince = 0;
    }
  }
}

function nextGovLevel(dir) {
  const now = govConfig(gov.level);
  let l = gov.level + dir;
  while (l > 0 && l < GOV_MAX && govConfig(l) === now) l += dir;
  return clamp(l, 0, GOV_MAX);
}

function setGovLevel(l) {
  if (l === gov.level) return;
  gov.level = l;
  setPixelRatio(clamp(prMax * RES_STEP[govRes()], prMin, prMax));
  buildComposer();
}

/* ---------------------------------------------------------------- messages */
function receive(raw) {
  let m;
  try { m = typeof raw === 'string' ? JSON.parse(raw) : raw; } catch (e) { return; }
  if (!m || !m.t) return;
  // One bad message is reported and dropped; the board keeps going.
  try { handle(m); } catch (e) { post({ t: 'error', msg: `${m.t}: ${e && e.message || e}` }); }
}

function handle(m) {
  switch (m.t) {
    case 'init': if (!renderer) { init(m); scene && (scene.add(markGroup), scene.add(tokenGroup)); } break;
    case 'state': applyState(m); break;
    case 'move': if (loaded) startMove(m.id, m.path, m.ms); invalidate(); break;
    case 'fx': if (loaded) burst(m.id, m.text, m.color, m.sparks, m.ms); break;
    case 'shake': shakeUntil = performance.now() + 320; break;
    case 'gfx': applyGfx(m.gfx); break;
    case 'drag': if (loaded) drag(m.dx, m.dy); break;
    case 'orbit': if (loaded) orbit(m.dx, m.dy); break;
    case 'pinch': if (loaded) pinch(m.k || 1, m.a || 0, m.fx, m.fy); break;
    case 'fling': if (loaded) flick(m.vx || 0, m.vy || 0); break;
    case 'pick': if (loaded) tap(m.x * innerWidth, m.y * innerHeight); break;
    case 'hidden': pauseLoop(); break;
    case 'visible': invalidate(3); wakeLoop(); break;
    case 'cam':
      if (!loaded) break;
      if (m.op === 'fit') { const h = homeView(); tweenTo(h.pos, h.target, m.ms ?? 380); }
      else if (m.op === 'zoom') zoom(m.k || 1.25);
      else if (m.op === 'push') pushIn(m.a, m.b, m.ms ?? 650);
      else if (m.op === 'pull') pullBack(m.ms ?? 650);
      else if (m.op === 'turn') turn(m.a || Math.PI / 4);
      else if (m.op === 'tilt') tilt();
      break;
  }
}
// stats/marked are for automated checks (frame rate, and where the highlighted spaces are).
const toScreen = v => { const p = v.clone().project(camera); return [(p.x + 1) / 2 * innerWidth, (1 - p.y) / 2 * innerHeight]; };
window.board = {
  receive,
  stats: () => ({
    calls: renderer.info.render.calls, triangles: renderer.info.render.triangles, frames: renderer.info.render.frame,
    geometries: renderer.info.memory.geometries, textures: renderer.info.memory.textures,
    pieces: pieces.size, pixelRatio: prNow, pixelRatioMax: prMax, composer: !!composer, governor: gov.level, ...fxOn(),
  }),
  marked: () => ({
    spaces: (marks.spaces || []).filter(id => spaces.has(id)).map(id => toScreen(at(id))),
    fighters: [...(marks.select || []), ...(marks.targets || [])].map(id => pieces.get(id)).filter(Boolean)
      .map(p => toScreen(p.group.position.clone().add(new V3(0, p.orb.position.y, 0)))),
  }),
};
if (window.chrome && window.chrome.webview) window.chrome.webview.addEventListener('message', e => receive(e.data));
window.addEventListener('message', e => {
  if (typeof e.data === 'string' && e.data.startsWith('board3d:')) return; // our own posts (no parent)
  if (e.source === window.parent && window.parent !== window) receive(e.data);
});
post({ t: 'loaded' });
