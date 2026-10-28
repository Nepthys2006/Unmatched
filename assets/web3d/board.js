/* Unmatched 3D board.
   Draws one of the 3D Map battlefields (assets/maps3d/<id>.glb) and the live pieces on it. The
   Flutter match screen drives it with JSON messages; the rules never run here. The page takes no
   input of its own: the game handles every touch and click (so its buttons always win) and sends
   camera moves and taps here. Map coordinates: maps.json x -> world x, y -> world z, top at y 0.

   Flutter -> page (window.board.receive(json), WebView2 web messages, or iframe postMessage):
     init   {art|glb, home, gfx, spaces:[{id,x,y}], links:[[a,b]]}  gfx {graphics settings}
            art {file, w, h, unitPx}: a printed map drawn on a slab (glb: a 3D Map model)
     state  {fighters:[{id,space,color,hero,hp,name,mini,fid,v}], marks:{...}, tokens:[...], focus:[id]}
            (mini: hero id, fid: fighter id, v: which of a hero's hero fighters; they pick the figure)
     move   {id, path:[space], ms}        fx {id, text, color, sparks, ms}        shake {}
     cam    {op:'fit'|'zoom'|'push'|'pull'|'turn'|'tilt', k, a, b, ms}
     drag {dx, dy} / orbit {dx, dy} (fractions of the view) / pinch {k, a} / pick {x, y}
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
   scale: render resolution as a share of the screen's pixels (capped at 2x); auto: let the
   frame-time governor lower it when frames run long; shadows 0-3 (off / 1024 / 2048 / 4096);
   aa: multisampling (fixed when the page starts); bloom: glow; ao: ambient occlusion;
   scenery: trees, rocks and buildings; brightness: exposure; labels: name plate size. */
const G = { scale: 1, auto: true, shadows: 2, aa: true, bloom: true, ao: false, scenery: true, brightness: 1, labels: 1, fps: false };
const SHADOW_SIZE = [512, 1024, 2048, 4096];
let prMax = 1, prNow = 1, prMin = .5;

/* ---------------------------------------------------------------- scene */
let renderer, scene, camera, lamp, composer = null;
let boardRoot = null, span = 14, box = new THREE.Box3();
const spaces = new Map();        // id -> {x, z, top}
let links = [];
let homeSide = 1;
let loaded = false, pendingState = null;
let dirty = 2;
const invalidate = (n = 2) => { dirty = Math.max(dirty, n); };

function setup() {
  try {
    renderer = new THREE.WebGLRenderer({ antialias: G.aa, powerPreference: 'high-performance', stencil: false });
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
    renderer.setSize(innerWidth, innerHeight);
    if (composer) composer.setSize(innerWidth, innerHeight);
    camera.aspect = innerWidth / Math.max(1, innerHeight);
    camera.updateProjectionMatrix();
    invalidate();
  });
  applyResolution();
  requestAnimationFrame(loop);
  return true;
}

function applyResolution() {
  prMax = clamp(Math.min(window.devicePixelRatio || 1, 2) * G.scale, .5, 3);
  prMin = Math.max(.75, prMax * .85); // never blurrier than 85% of the chosen resolution
  prNow = prMax;
  renderer.setPixelRatio(prNow);
  renderer.setSize(innerWidth, innerHeight);
  if (composer) { composer.setPixelRatio(prNow); composer.setSize(innerWidth, innerHeight); }
  invalidate();
}

/** Bloom and ambient occlusion need a composer; without them the scene renders straight out. */
function buildComposer() {
  if (composer) { composer.dispose(); composer = null; }
  if (!G.bloom && !G.ao) return;
  const isWebGl2 = renderer.capabilities.isWebGL2;
  const rt = new THREE.WebGLRenderTarget(1, 1, {
    type: THREE.HalfFloatType,
    samples: (G.aa && isWebGl2) ? 2 : 0,
  });
  composer = new EffectComposer(renderer, rt);
  composer.setPixelRatio(prNow);
  composer.setSize(innerWidth, innerHeight);
  composer.addPass(new RenderPass(scene, camera));
  if (G.ao) {
    const ao = new GTAOPass(scene, camera, innerWidth, innerHeight);
    ao.blendIntensity = .85;
    ao.updateGtaoMaterial({ radius: .32, distanceExponent: 1.4, thickness: 1, scale: 1.1, samples: 12 });
    ao.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 4, rings: 2, samples: 16 });
    composer.addPass(ao);
  }
  if (G.bloom) composer.addPass(new UnrealBloomPass(new THREE.Vector2(Math.floor(innerWidth / 2), Math.floor(innerHeight / 2)), .32, .5, .88));
  composer.addPass(new OutputPass());
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
  renderer.shadowMap.needsUpdate = true;
  invalidate();
}

/** Applies graphics settings; `first` when the page starts. */
function applyGfx(g, first) {
  const old = { ...G };
  Object.assign(G, g || {});
  if (!renderer) return;
  if (first || old.scale !== G.scale) applyResolution();
  if (first || old.shadows !== G.shadows) applyShadows();
  if (first || old.bloom !== G.bloom || old.ao !== G.ao) buildComposer();
  renderer.toneMappingExposure = G.brightness;
  const scenery = boardRoot && boardRoot.getObjectByName('Scenery');
  if (scenery && scenery.visible !== G.scenery) { scenery.visible = G.scenery; renderer.shadowMap.needsUpdate = true; }
  for (const p of pieces.values()) sizePiece(p);
  if (!G.auto && prNow !== prMax) applyResolution();
  invalidate();
}

/* ---------------------------------------------------------------- loading */
async function init(msg) {
  Object.assign(G, msg.gfx || {});
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
  boardRoot.traverse(o => {
    if (!o.isMesh) return;
    o.userData.casts = isUnder(o, 'Scenery');
    const m = o.material;
    if (m && m.map) m.map.anisotropy = Math.min(16, renderer.capabilities.getMaxAnisotropy());
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
  scene.background = new THREE.Color('#101114');
  scene.fog.color.set('#101114');
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
    if (o.isMesh && o.material && o.material.color && o.geometry.type === 'PlaneGeometry' && o.position.y < 0) o.material.color.set('#1c1b19');
  });
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
   straight down... up, theta around). The game sends drags, pinches and orbits. */
let camTween = null, shakeUntil = 0, preCombat = null;
const rig = { target: new V3(), r: 20, phi: .62, theta: 0 };
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
}

function syncCamera() {
  if (!box.isEmpty()) {
    rig.target.x = clamp(rig.target.x, box.min.x - 3, box.max.x + 3);
    rig.target.z = clamp(rig.target.z, box.min.z - 3, box.max.z + 3);
  }
  camera.position.copy(spherical(rig.target, rig.r, rig.phi, rig.theta));
  camera.lookAt(rig.target);
  invalidate();
}

/** One finger / left button: slide the board under the finger. */
function drag(dx, dy) {
  camTween = null;
  const k = 2 * rig.r * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  const right = new V3(Math.cos(rig.theta), 0, -Math.sin(rig.theta));
  const fwd = new V3(-Math.sin(rig.theta), 0, -Math.cos(rig.theta));
  rig.target.addScaledVector(right, -dx * k * camera.aspect).addScaledVector(fwd, dy * k / Math.max(.35, Math.cos(rig.phi)));
  syncCamera();
}
/** Right button: turn around the board and tilt. */
function orbit(dx, dy) {
  camTween = null;
  rig.theta -= dx * Math.PI * 1.4;
  rig.phi = clamp(rig.phi - dy * Math.PI * .8, PHI_MIN, PHI_MAX);
  syncCamera();
}
/** Two fingers: pinch to zoom (k > 1 = closer) and twist to turn. */
function pinch(k, a) {
  camTween = null;
  rig.r = clamp(rig.r / k, R_MIN, rMax());
  rig.theta -= a || 0;
  syncCamera();
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
  if (!ms) { rig.target.copy(to.target); rig.r = r; rig.phi = phi; rig.theta = to.theta; syncCamera(); return; }
  camTween = { from: { target: rig.target.clone(), r: rig.r, phi: rig.phi, theta: rig.theta }, to, start: performance.now(), ms };
}

function tweenTo(pos, target, ms) {
  const o = pos.clone().sub(target), r = o.length();
  rigTo(target, r, Math.acos(clamp(o.y / r, -1, 1)), Math.atan2(o.x, o.z), ms);
}

function zoom(k) { rigTo(rig.target, clamp(rig.r / k, R_MIN, rMax()), rig.phi, rig.theta, 220); }
function turn(a) { rigTo(rig.target, rig.r, rig.phi, rig.theta + a, 380); }
/** Toggles between the seated view and looking straight down. */
function tilt() { rigTo(rig.target, rig.r, rig.phi > .3 ? PHI_MIN : .62, rig.theta, 380); }

/** The dramatic push-in: a low camera beside the two fighters, looking across the duel. */
function pushIn(a, b, ms) {
  const A = spaces.get(a), B = spaces.get(b);
  if (!A || !B) return;
  preCombat = { pos: camera.position.clone(), target: rig.target.clone() };
  const mid = new V3((A.x + B.x) / 2, (A.top + B.top) / 2 + .25, (A.z + B.z) / 2);
  const along = new V3(B.x - A.x, 0, B.z - A.z);
  const len = along.length();
  // Look across the line between them, from whichever side the camera is already on.
  let side = len > 1e-3 ? new V3(-along.z, 0, along.x).normalize() : new V3(0, 0, homeSide);
  const cur = camera.position.clone().sub(mid).setY(0);
  if (cur.dot(side) < 0) side.negate();
  const polar = 1.02;
  const tanH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  // The combat cards fill the top of the screen, so frame the duel in the lower part.
  const dist = clamp((len + 2.4) / (.6 * 2 * tanH * camera.aspect), 6.5, span * .9);
  const azim = Math.atan2(side.x, side.z);
  // Aiming past the fighters (away from the camera) moves them down the screen.
  const target = mid.clone().addScaledVector(side, -.5 * tanH * dist / Math.cos(polar));
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
const RETICLE = canvasTex(256, 256, (g, w) => {
  g.strokeStyle = '#ff5b4e'; g.lineWidth = 14; g.lineCap = 'round';
  g.beginPath(); g.arc(w / 2, w / 2, w * .36, 0, TAU); g.stroke();
  for (let i = 0; i < 4; i++) {
    const a = i * Math.PI / 2, c = Math.cos(a), s = Math.sin(a);
    g.beginPath(); g.moveTo(w / 2 + c * w * .28, w / 2 + s * w * .28); g.lineTo(w / 2 + c * w * .47, w / 2 + s * w * .47); g.stroke();
  }
});

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

/** Shield badge over the fighter: its portrait (hero avatar or sidekick token) in a shield rimmed
    in the player's colour, and a name plate with the health heart. Redrawn when hp, name or colour
    change, and once the portrait has loaded. */
function drawLabel(p) {
  const c = p.label.material.map.image, g = c.getContext('2d'), W = c.width, H = c.height;
  g.clearRect(0, 0, W, H);
  const sx = W * .22, sy = 6, sw = W * .56, sh = H * .58;
  g.save();
  g.shadowColor = 'rgba(0,0,0,.55)'; g.shadowBlur = 10; g.shadowOffsetY = 3;
  shieldPath(g, sx, sy, sw, sh); g.fillStyle = p.color; g.fill();
  g.restore();
  const ix = sx + sw * .07, iy = sy + sw * .07, iw = sw * .86, ih = sh - sw * .16;
  g.save();
  shieldPath(g, ix, iy, iw, ih); g.clip();
  g.fillStyle = '#1a1b20'; g.fillRect(ix, iy, iw, ih);
  const img = p.portrait;
  if (img && img.complete && img.naturalWidth) {
    const s = Math.max(iw / img.naturalWidth, ih / img.naturalHeight);
    const dw = img.naturalWidth * s, dh = img.naturalHeight * s;
    // avatars are framed from the top (faces); round tokens are centred
    g.drawImage(img, ix + (iw - dw) / 2, p.hero ? iy : iy + (ih - dh) / 2, dw, dh);
  }
  g.restore();
  shieldPath(g, ix, iy, iw, ih); g.lineWidth = 3; g.strokeStyle = 'rgba(255,255,255,.75)'; g.stroke();

  // name plate with the heart at its left end
  const ph = H * .2, py = sh + 16;
  g.font = `700 ${ph * .62}px ${fontFamily}`;
  const name = p.name.toUpperCase();
  const tw = Math.min(g.measureText(name).width, W - ph * 2.2);
  const plateW = tw + ph * .9, x0 = (W - plateW + ph * .7) / 2;
  g.fillStyle = 'rgba(14,15,18,.88)';
  roundRect(g, x0, py, plateW, ph, ph * .14); g.fill();
  g.fillStyle = p.color;
  g.fillRect(x0, py, ph * .1, ph);
  g.fillStyle = '#ece6d8';
  g.textBaseline = 'middle';
  g.fillText(name, x0 + ph * .5, py + ph * .54, W - ph * 2.2);
  const hs = ph * 1.35, hx = x0 - hs * .72, hy = py + (ph - hs) / 2;
  heartPath(g, hx, hy, hs); g.fillStyle = '#d8323a'; g.fill();
  g.lineWidth = ph * .08; g.strokeStyle = '#ece6d8'; g.stroke();
  g.fillStyle = '#fff';
  g.font = `800 ${hs * .46}px ${fontFamily}`;
  g.textAlign = 'center';
  g.fillText(String(p.hp), hx + hs / 2, hy + hs * .47);
  g.textAlign = 'left';

  // the hero's pieces under the plate: a card with its name, tokens one by one, or a counter
  const items = (p.items || []).slice(0, 2);
  let ry = py + ph + 10;
  const rh = ph * .82;
  for (const it of items) {
    const color = it.c || '#ece6d8';
    let text = it.k === 'card' ? it.t : (it.k === 'tokens' && (it.m ?? it.n ?? 0) <= 6 ? '' : `${it.t} ${it.m != null ? `${it.n}/${it.m}` : it.n}`);
    g.font = `700 ${rh * .56}px ${fontFamily}`;
    const tokens = it.k === 'tokens' && (it.m ?? it.n ?? 0) <= 6 ? (it.m ?? it.n ?? 0) : 0;
    const tw2 = Math.min(g.measureText(text).width, W - rh * 3);
    const w = rh * 1.1 + (text ? tw2 + rh * .35 : 0) + tokens * rh * .78 + (tokens ? rh * .2 : 0);
    const x = (W - w) / 2;
    g.fillStyle = 'rgba(14,15,18,.9)';
    roundRect(g, x, ry, w, rh, rh * .2); g.fill();
    g.lineWidth = 3; g.strokeStyle = color; g.stroke();
    g.font = `${rh * .62}px "Segoe UI Emoji","Apple Color Emoji","Noto Color Emoji",sans-serif`;
    g.textBaseline = 'middle'; g.textAlign = 'left';
    if (tokens) {
      for (let k = 0; k < tokens; k++) {
        g.globalAlpha = k < (it.n || 0) ? 1 : .25;
        g.fillText(it.e, x + rh * .2 + k * rh * .78, ry + rh * .54);
      }
      g.globalAlpha = 1;
      g.font = `700 ${rh * .5}px ${fontFamily}`; g.fillStyle = color;
      g.fillText(it.t, x + rh * .3 + tokens * rh * .78, ry + rh * .54);
    } else {
      g.fillText(it.e, x + rh * .2, ry + rh * .54);
      g.font = `700 ${rh * .56}px ${fontFamily}`; g.fillStyle = '#fff';
      g.fillText(text, x + rh * 1.1, ry + rh * .56, W - rh * 3);
    }
    ry += rh + 6;
  }
  p.label.material.map.needsUpdate = true;
}
function shieldPath(g, x, y, w, h) {
  const r = w * .12;
  g.beginPath();
  g.moveTo(x + r, y);
  g.lineTo(x + w - r, y);
  g.quadraticCurveTo(x + w, y, x + w, y + r);
  g.lineTo(x + w, y + h * .5);
  g.bezierCurveTo(x + w, y + h * .78, x + w * .72, y + h * .9, x + w / 2, y + h);
  g.bezierCurveTo(x + w * .28, y + h * .9, x, y + h * .78, x, y + h * .5);
  g.lineTo(x, y + r);
  g.quadraticCurveTo(x, y, x + r, y);
  g.closePath();
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
  const s = Math.min(1, (coin ? 80 : 150) / Math.max(img.width, img.height));
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
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
    t.userData.shared = true; // cached across pieces: never disposed with one
    return t;
  });
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
  const body = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: fig.tex, alphaTest: .5, roughness: .62 }));
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
  p.label.position.y = h + sh + .06;
  renderer.shadowMap.needsUpdate = true;
  invalidate(3);
}

/** Figures turn about their own upright axis to face the camera (badges are sprites and already do). */
function faceCamera() {
  for (const p of pieces.values()) {
    if (!p.pivot) continue;
    const g = p.group.position;
    p.pivot.rotation.y = Math.atan2(camera.position.x - g.x, camera.position.z - g.z);
  }
}

/* ---------------------------------------------------------------- pieces */
const pieces = new Map();   // fighter uid -> piece
const orbGeo = new THREE.SphereGeometry(1, 32, 20);
const baseGeo = new THREE.RingGeometry(.74, 1, 40).rotateX(-Math.PI / 2);
const ringGeo = new THREE.TorusGeometry(1, .07, 8, 48).rotateX(Math.PI / 2);
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
  const ring = new THREE.Mesh(ringGeo, basic(SELECT));
  ring.scale.setScalar(rad * 1.9);
  ring.position.y = .05;
  ring.visible = false;
  const reticle = new THREE.Sprite(new THREE.SpriteMaterial({ map: RETICLE, depthTest: false, transparent: true, toneMapped: false }));
  reticle.position.y = orb.position.y;
  reticle.scale.setScalar(rad * 4.2);
  reticle.renderOrder = 9;
  reticle.visible = false;
  const lc = document.createElement('canvas'); lc.width = 320; lc.height = 400;
  const lt = new THREE.CanvasTexture(lc); lt.colorSpace = THREE.SRGBColorSpace;
  const label = new THREE.Sprite(new THREE.SpriteMaterial({ map: lt, depthTest: false, transparent: true, toneMapped: false }));
  label.userData.base = f.hero ? 1 : (f.small ? .62 : .8);
  label.center.set(.5, 0);
  label.position.y = orb.position.y + rad + .08;
  label.renderOrder = 10;
  label.userData.fid = f.id;
  group.add(base, ring, orb, glow, reticle, label);
  scene.add(group);
  const p = { id: f.id, group, orb, glow, base, ring, reticle, label, rad, hitR: rad * 1.5, color: f.color, name: f.name, hp: f.hp, hero: f.hero, space: f.space, anim: null, items: f.items || [], itemsKey: JSON.stringify(f.items || []) };
  // portrait for the badge: the hero's avatar, or a sidekick's own token
  if (f.mini) {
    p.portrait = new Image();
    p.portrait.onload = () => { drawLabel(p); invalidate(); };
    p.portrait.src = f.hero ? `../heroes/${f.mini}/avatar.webp` : `../heroes/${f.mini}/${f.fid}.webp`;
  }
  sizePiece(p);
  drawLabel(p);
  fontReady.then(() => { drawLabel(p); invalidate(); });
  buildFigure(p, f);
  return p;
}

/** Badge size and orb glow follow the graphics settings. */
function sizePiece(p) {
  const ls = p.label.userData.base * G.labels * .8;
  p.label.scale.set(ls, ls * 400 / 320, 1);
  p.orb.material.emissiveIntensity = G.bloom ? 1.25 : .5;
}

function disposePiece(p) {
  scene.remove(p.group);
  if (p.tail) scene.remove(p.tail);
  p.group.traverse(o => {
    if (p.figure && o.geometry && o.geometry !== podiumGeo && o.parent && o.parent !== p.group) o.geometry.dispose();
    for (const m of [].concat(o.material || [])) {
      if (m.map && m.map !== GLOW && m.map !== RETICLE && !m.map.userData.shared) m.map.dispose();
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
    fill.renderOrder = ring.renderOrder = 2;
    pulseMats.push(fill.material);
    markGroup.add(fill, ring);
  }
  if (m.pendingSpace != null && spaces.has(m.pendingSpace)) {
    const r = new THREE.Mesh(pendRing, basic(BONE));
    r.position.copy(at(m.pendingSpace, .006)); r.renderOrder = 3;
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

function buildTokens(tokens) {
  clearGroup(tokenGroup);
  const shadowCount = {}, insightCount = {};
  for (const t of tokens || []) {
    if (t.kind === 'fog' && spaces.has(t.space)) {
      // Invisible Man's fog: a bank of cloud puffs over a soft grey shadow on the space.
      const c = at(t.space, 0);
      const shade = new THREE.Mesh(spaceFill, basic('#5a6478', .45));
      shade.position.set(c.x, c.y + .004, c.z);
      shade.scale.setScalar(1.25);
      tokenGroup.add(shade);
      for (const [dx, dy, dz, s] of [[-.2, .2, .06, .5], [.2, .22, .1, .48], [0, .3, -.14, .56], [.04, .18, .2, .44], [-.06, .42, 0, .46], [.16, .38, -.06, .4]]) {
        const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: PUFF, transparent: true, depthWrite: false, opacity: .96 }));
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
  if (!loaded) { pendingState = s; return; }
  pendingState = null;
  const seen = new Set();
  for (const f of s.fighters) {
    seen.add(f.id);
    let p = pieces.get(f.id);
    if (!p) { p = makePiece(f); pieces.set(f.id, p); }
    const items = JSON.stringify(f.items || []);
    if (p.hp !== f.hp || p.name !== f.name || p.color !== f.color || p.itemsKey !== items) {
      p.itemsKey = items;
      p.items = f.items || [];
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
  const tex = canvasTex(256, 128, (g, w, h) => {
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
  // The piece's own position (not its space's centre), so a tap picks between fighters sharing a space.
  if (best && spaces.has(best.space)) { post({ t: 'tap', x: best.group.position.x, y: best.group.position.z }); return; }
  // Otherwise the nearest point on the board's surface (bridges are a little higher).
  const plane = new THREE.Plane(new V3(0, 1, 0), -.02);
  const pt = raycaster.ray.intersectPlane(plane, new V3());
  if (pt) post({ t: 'tap', x: pt.x, y: pt.z });
}

/* ---------------------------------------------------------------- frame loop */
function loop(now) {
  requestAnimationFrame(loop);
  let busy = false;

  if (camTween) {
    const t = clamp((now - camTween.start) / camTween.ms, 0, 1), k = ease(t), a = camTween.from, b = camTween.to;
    rig.target.lerpVectors(a.target, b.target, k);
    rig.r = a.r + (b.r - a.r) * k;
    rig.phi = a.phi + (b.phi - a.phi) * k;
    rig.theta = a.theta + (b.theta - a.theta) * k;
    syncCamera();
    if (t >= 1) camTween = null;
    busy = true;
  }

  for (const p of pieces.values()) {
    const a = p.anim;
    if (!a) continue;
    busy = true;
    const segs = a.path.length - 1;
    const x = clamp((now - a.start) / a.ms, 0, 1) * segs;
    const i = Math.min(Math.floor(x), segs - 1), u = ease(x - i);
    const A = spaces.get(a.path[i]), B = spaces.get(a.path[i + 1]);
    p.group.position.set(A.x + (B.x - A.x) * u, A.top + (B.top - A.top) * u + Math.sin(Math.PI * u) * .28, A.z + (B.z - A.z) * u);
    if (x >= segs) { p.anim = null; placePiece(p); }
    renderer.shadowMap.needsUpdate = true;
  }

  if (pulsing) {
    busy = true;
    const ph = .5 - .5 * Math.cos(now / 900 * TAU);
    for (const m of pulseMats) m.opacity = .22 + .3 * ph;
    for (const p of pieces.values()) {
      if (p.ring.visible) p.ring.scale.setScalar(p.rad * (p.ring.userData.pulse ? 1.85 + .2 * ph : 1.9));
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
    busy = true;
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
    busy = true;
    const k = (shakeUntil - now) / 320;
    shake = new V3(Math.sin(now * .09) * .06 * k, 0, Math.cos(now * .11) * .04 * k);
    camera.position.add(shake);
  }

  if (busy || dirty > 0) {
    faceCamera();
    govern(now);
    if (composer) composer.render(); else renderer.render(scene, camera);
    fpsFrames++;
    if (dirty > 0) dirty--;
    if (busy) dirty = Math.max(dirty, 1);
  }
  if (shake) camera.position.sub(shake);
  if (G.fps && now - fpsStart >= 1000) {
    post({ t: 'fps', v: Math.round(fpsFrames * 1000 / (now - fpsStart)) });
    fpsFrames = 0; fpsStart = now;
  }
}
let fpsFrames = 0, fpsStart = 0;

/* Frame-time governor: while frames render back to back, lower the resolution when they run
   long (slow phone, busy browser) and raise it again when there's headroom. */
let govLast = 0, govSum = 0, govN = 0;
function govern(now) {
  const dt = now - govLast;
  govLast = now;
  if (!G.auto || dt <= 0 || dt > 100) return; // off, or the first frame after idle
  govSum += dt; govN++;
  if (govN < 45) return;
  const avg = govSum / govN;
  govSum = govN = 0;
  let next = prNow;
  if (avg > 26) next = Math.max(prMin, prNow * .9);
  else if (avg < 15 && prNow < prMax) next = Math.min(prMax, prNow * 1.05);
  if (Math.abs(next - prNow) > .01) {
    prNow = next;
    renderer.setPixelRatio(prNow);
    renderer.setSize(innerWidth, innerHeight);
    if (composer) { composer.setPixelRatio(prNow); composer.setSize(innerWidth, innerHeight); }
  }
}

/* ---------------------------------------------------------------- messages */
function receive(raw) {
  let m;
  try { m = typeof raw === 'string' ? JSON.parse(raw) : raw; } catch (e) { return; }
  if (!m || !m.t) return;
  switch (m.t) {
    case 'init': if (!renderer) { init(m); scene && (scene.add(markGroup), scene.add(tokenGroup)); } break;
    case 'state': applyState(m); break;
    case 'move': if (loaded) startMove(m.id, m.path, m.ms); invalidate(); break;
    case 'fx': if (loaded) burst(m.id, m.text, m.color, m.sparks, m.ms); break;
    case 'shake': shakeUntil = performance.now() + 320; break;
    case 'gfx': applyGfx(m.gfx); break;
    case 'drag': if (loaded) drag(m.dx, m.dy); break;
    case 'orbit': if (loaded) orbit(m.dx, m.dy); break;
    case 'pinch': if (loaded) pinch(m.k || 1, m.a || 0); break;
    case 'pick': if (loaded) tap(m.x * innerWidth, m.y * innerHeight); break;
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
  stats: () => ({ calls: renderer.info.render.calls, triangles: renderer.info.render.triangles, pixelRatio: prNow, composer: !!composer }),
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
