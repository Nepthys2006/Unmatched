/* Unmatched 3D board.
   Draws one of the 3D Map battlefields (assets/maps3d/<id>.glb) and the live pieces on it. The
   Flutter match screen drives it with JSON messages and gets taps back; the rules never run
   here. Map coordinates: maps.json x -> world x, maps.json y -> world z, board top at y = 0.

   Flutter -> page (window.board.receive(json), WebView2 web messages, or iframe postMessage):
     init   {glb, quality, home, spaces:[{id,x,y}], links:[[a,b]]}
     state  {fighters:[{id,space,color,hero,hp,name}], marks:{...}, tokens:[...], focus:[id]}
     move   {id, path:[space], ms}        fx {id, text, color, sparks, ms}
     cam    {op:'fit'|'zoom'|'push'|'pull', k, a, b, ms}        shake {}
   Page -> Flutter: ready, progress {p}, error {msg}, tap {x, y}. */
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

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

/* pr = highest pixel ratio; phones (coarse pointer) get less, and the frame-time governor in
   loop() lowers it further if frames run long. */
const coarse = matchMedia('(pointer: coarse)').matches;
const QUALITY = {
  low: { pr: 1, prPhone: .85, aa: false, shadow: 0 },
  medium: { pr: 1.5, prPhone: 1.25, aa: true, shadow: 1024 },
  high: { pr: 2, prPhone: 1.75, aa: true, shadow: 2048 },
};
let prMax = 1, prNow = 1;

/* ---------------------------------------------------------------- scene */
let renderer, scene, camera, controls, lamp, Q;
let boardRoot = null, span = 14, box = new THREE.Box3();
const spaces = new Map();        // id -> {x, z, top}
let links = [];
let homeSide = 1;
let loaded = false, pendingState = null;
let dirty = 2;
const invalidate = (n = 2) => { dirty = Math.max(dirty, n); };

function setup(quality) {
  Q = QUALITY[quality] || QUALITY.medium;
  try {
    renderer = new THREE.WebGLRenderer({ antialias: Q.aa, powerPreference: 'high-performance', stencil: false });
  } catch (e) {
    post({ t: 'error', fatal: true, msg: 'WebGL is not available' });
    return false;
  }
  prMax = prNow = Math.min(window.devicePixelRatio || 1, coarse ? Q.prPhone : Q.pr);
  renderer.setPixelRatio(prNow);
  renderer.setSize(innerWidth, innerHeight);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.shadowMap.enabled = Q.shadow > 0;
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
  camera.position.set(0, 12, 10);
  controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = .1;
  controls.screenSpacePanning = false;
  controls.minPolarAngle = .05;
  controls.maxPolarAngle = 1.3;
  controls.minDistance = 2.5;
  // One finger / left button scrolls the map like the 2D board; two fingers / right button orbit.
  controls.mouseButtons = { LEFT: THREE.MOUSE.PAN, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.ROTATE };
  controls.touches = { ONE: THREE.TOUCH.PAN, TWO: THREE.TOUCH.DOLLY_ROTATE };
  controls.addEventListener('start', () => { camTween = null; });
  controls.addEventListener('change', () => invalidate());

  // A warm table lamp, a cool fill and a faint bounce, as on the 3D Map table.
  scene.add(new THREE.HemisphereLight('#dfe6ff', '#2b1d12', .3));
  lamp = new THREE.SpotLight('#ffd2a0', 100, 0, .7, .85, 2);
  lamp.castShadow = Q.shadow > 0;
  lamp.shadow.mapSize.set(Q.shadow || 512, Q.shadow || 512);
  lamp.shadow.bias = -.00015;
  lamp.shadow.normalBias = .025;
  const fill = new THREE.DirectionalLight('#a9bfff', .38);
  scene.add(lamp, lamp.target, fill);
  scene.userData.fill = fill;

  addEventListener('resize', () => {
    renderer.setSize(innerWidth, innerHeight);
    camera.aspect = innerWidth / Math.max(1, innerHeight);
    camera.updateProjectionMatrix();
    invalidate();
  });
  setupInput();
  requestAnimationFrame(loop);
  return true;
}

/* ---------------------------------------------------------------- loading */
async function init(msg) {
  if (!setup(msg.quality)) return;
  homeSide = msg.home || 1;
  for (const s of msg.spaces) spaces.set(s.id, { x: s.x, z: s.y, top: .003 });
  links = msg.links || [];
  const loader = new GLTFLoader();
  loader.setMeshoptDecoder(MeshoptDecoder);
  let gltf;
  try {
    gltf = await loader.loadAsync(msg.glb, e => { if (e.total) post({ t: 'progress', p: e.loaded / e.total }); });
  } catch (e) {
    post({ t: 'error', fatal: true, msg: 'Could not load the map: ' + (e && e.message || e) });
    return;
  }
  boardRoot = gltf.scene;
  const shadows = Q.shadow > 0;
  boardRoot.updateMatrixWorld(true);
  boardRoot = mergeStatic(boardRoot);
  boardRoot.traverse(o => {
    if (!o.isMesh) return;
    const scenery = isUnder(o, 'Scenery');
    o.receiveShadow = shadows;
    o.castShadow = shadows && scenery;
    const m = o.material;
    if (m && m.map) m.map.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
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
  controls.maxDistance = span * 2.2;
  const table = new THREE.Mesh(
    new THREE.PlaneGeometry(span * 5, span * 5).rotateX(-Math.PI / 2),
    new THREE.MeshStandardMaterial({ color: '#2b2019', roughness: .82 }),
  );
  table.position.y = box.min.y - .002;
  table.receiveShadow = shadows;
  scene.add(table);

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
  camera.position.copy(home.pos);
  controls.target.copy(home.target);
  controls.update();
  loaded = true;
  renderer.shadowMap.needsUpdate = true;
  if (pendingState) applyState(pendingState);
  invalidate(3);
  // Two frames so the first picture is on screen before the cover is lifted.
  requestAnimationFrame(() => requestAnimationFrame(() => post({ t: 'ready' })));
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

/* ---------------------------------------------------------------- camera */
let camTween = null, shakeUntil = 0, preCombat = null;
const spherical = (target, dist, polar, azim) =>
  target.clone().add(new V3(Math.sin(polar) * Math.sin(azim), Math.cos(polar), Math.sin(polar) * Math.cos(azim)).multiplyScalar(dist));

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

function tweenTo(pos, target, ms) {
  if (!ms) {
    camera.position.copy(pos); controls.target.copy(target); controls.update(); invalidate();
    return;
  }
  camTween = { p0: camera.position.clone(), t0: controls.target.clone(), p1: pos, t1: target, start: performance.now(), ms };
}

function zoom(k) {
  const off = camera.position.clone().sub(controls.target);
  const len = clamp(off.length() / k, controls.minDistance, controls.maxDistance);
  tweenTo(controls.target.clone().add(off.setLength(len)), controls.target.clone(), 220);
}

/** The dramatic push-in: a low camera beside the two fighters, looking across the duel. */
function pushIn(a, b, ms) {
  const A = spaces.get(a), B = spaces.get(b);
  if (!A || !B) return;
  preCombat = { pos: camera.position.clone(), target: controls.target.clone() };
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
const PUFF = canvasTex(128, 128, (g, w) => {
  const r = g.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2);
  r.addColorStop(0, 'rgba(226,231,238,.95)'); r.addColorStop(.55, 'rgba(214,220,228,.6)'); r.addColorStop(1, 'rgba(214,220,228,0)');
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

/** Name plate with the health heart, drawn into the fighter's label canvas. */
function drawLabel(p) {
  const c = p.label.material.map.image, g = c.getContext('2d'), W = c.width, H = c.height;
  g.clearRect(0, 0, W, H);
  g.font = `700 ${H * .44}px ${fontFamily}`;
  const name = p.name.toUpperCase();
  const tw = Math.min(g.measureText(name).width, W - H * 1.3);
  const plateW = tw + H * .5, x0 = (W - plateW - H * .7) / 2 + H * .7;
  g.fillStyle = 'rgba(14,15,18,.86)';
  roundRect(g, x0, H * .22, plateW, H * .56, H * .08); g.fill();
  g.fillStyle = p.color;
  g.fillRect(x0, H * .22, H * .06, H * .56);
  g.fillStyle = '#ece6d8';
  g.textBaseline = 'middle';
  g.fillText(name, x0 + H * .24, H * .52, W - H * 1.3);
  // Heart badge overlapping the plate's left end.
  const hs = H * .9, hx = x0 - hs * .72, hy = (H - hs) / 2;
  heartPath(g, hx, hy, hs); g.fillStyle = '#d8323a'; g.fill();
  g.lineWidth = H * .05; g.strokeStyle = '#ece6d8'; g.stroke();
  g.fillStyle = '#fff';
  g.font = `800 ${H * .42}px ${fontFamily}`;
  g.textAlign = 'center';
  g.fillText(String(p.hp), hx + hs / 2, hy + hs * .47);
  g.textAlign = 'left';
  p.label.material.map.needsUpdate = true;
}
function roundRect(g, x, y, w, h, r) {
  g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();
}

/* ---------------------------------------------------------------- pieces */
const pieces = new Map();   // fighter uid -> piece
const orbGeo = new THREE.SphereGeometry(1, 32, 20);
const baseGeo = new THREE.RingGeometry(.74, 1, 40).rotateX(-Math.PI / 2);
const ringGeo = new THREE.TorusGeometry(1, .07, 8, 48).rotateX(Math.PI / 2);
const basic = (color, opacity = 1) => new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false, toneMapped: false });

function makePiece(f) {
  const rad = f.hero ? .23 : .165;
  const color = new THREE.Color(f.color);
  const group = new THREE.Group();
  const orb = new THREE.Mesh(orbGeo, new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: .5, roughness: .25, metalness: .05 }));
  orb.scale.setScalar(rad);
  orb.position.y = rad + .14;
  orb.castShadow = Q.shadow > 0;
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
  const lc = document.createElement('canvas'); lc.width = 384; lc.height = 96;
  const lt = new THREE.CanvasTexture(lc); lt.colorSpace = THREE.SRGBColorSpace;
  const label = new THREE.Sprite(new THREE.SpriteMaterial({ map: lt, depthTest: false, transparent: true, toneMapped: false }));
  const ls = f.hero ? 1.25 : 1;
  label.scale.set(ls * 1.3, ls * .325, 1);
  label.position.y = orb.position.y + rad + .3;
  label.renderOrder = 10;
  label.userData.fid = f.id;
  group.add(base, ring, orb, glow, reticle, label);
  scene.add(group);
  const p = { id: f.id, group, orb, glow, base, ring, reticle, label, rad, color: f.color, name: f.name, hp: f.hp, space: f.space, anim: null };
  drawLabel(p);
  fontReady.then(() => { drawLabel(p); invalidate(); });
  return p;
}

function disposePiece(p) {
  scene.remove(p.group);
  p.group.traverse(o => {
    if (o.material) { if (o.material.map && o.material.map !== GLOW && o.material.map !== RETICLE) o.material.map.dispose(); o.material.dispose(); }
  });
}

function placePiece(p) {
  const s = spaces.get(p.space);
  if (s) p.group.position.set(s.x, s.top, s.z);
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
  for (const t of tokens || []) {
    if (t.kind === 'fog' && spaces.has(t.space)) {
      const c = at(t.space, .22);
      for (const [dx, dz, s] of [[-.16, .05, .55], [.15, .08, .5], [0, -.12, .6], [.03, .14, .45]]) {
        const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: PUFF, transparent: true, depthWrite: false, opacity: .8 }));
        sp.position.set(c.x + dx, c.y + s * .1, c.z + dz);
        sp.scale.setScalar(s);
        tokenGroup.add(sp);
      }
    } else if (t.a != null && spaces.has(t.a) && spaces.has(t.b)) {
      const m = at(t.a).lerp(at(t.b), .5);
      const d = new THREE.Mesh(new THREE.OctahedronGeometry(.15, 0), new THREE.MeshStandardMaterial({ color: '#1c1c1c', roughness: .5, emissive: '#c8352c', emissiveIntensity: .25 }));
      d.scale.y = .45;
      d.position.set(m.x, m.y + .08, m.z);
      d.castShadow = Q.shadow > 0;
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
    if (p.hp !== f.hp || p.name !== f.name || p.color !== f.color) {
      const recolor = p.color !== f.color;
      p.hp = f.hp; p.name = f.name; p.color = f.color;
      if (recolor) {
        const c = new THREE.Color(f.color);
        p.orb.material.color.copy(c); p.orb.material.emissive.copy(c); p.glow.material.color.copy(c); p.base.material.color.copy(c);
      }
      drawLabel(p);
    }
    p.space = f.space;
    if (!p.anim) placePiece(p);
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
  if (sparks && Q === QUALITY.high) {
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

/* ---------------------------------------------------------------- input */
function setupInput() {
  const el = renderer.domElement;
  const downs = new Map();
  el.addEventListener('pointerdown', e => downs.set(e.pointerId, { x: e.clientX, y: e.clientY, t: performance.now(), multi: downs.size > 0 }));
  el.addEventListener('pointerup', e => {
    const d = downs.get(e.pointerId);
    downs.delete(e.pointerId);
    if (!d || d.multi || downs.size) return;
    if (Math.hypot(e.clientX - d.x, e.clientY - d.y) > 10 || performance.now() - d.t > 600) return;
    if (e.button !== undefined && e.button !== 0) return;
    tap(e.clientX, e.clientY);
  });
  el.addEventListener('pointercancel', e => downs.delete(e.pointerId));
  el.addEventListener('contextmenu', e => e.preventDefault());
}

const raycaster = new THREE.Raycaster();
function tap(cx, cy) {
  if (!loaded) return;
  const ndc = new THREE.Vector2(cx / innerWidth * 2 - 1, -(cy / innerHeight) * 2 + 1);
  raycaster.setFromCamera(ndc, camera);
  // Fighters first: the orb and its name plate both count as the fighter.
  const targets = [];
  for (const p of pieces.values()) targets.push(p.orb, p.label);
  const hit = raycaster.intersectObjects(targets, false)[0];
  if (hit) {
    const p = pieces.get(hit.object.userData.fid), s = p && spaces.get(p.space);
    if (s) { post({ t: 'tap', x: s.x, y: s.z }); return; }
  }
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
    const t = clamp((now - camTween.start) / camTween.ms, 0, 1), k = ease(t);
    camera.position.lerpVectors(camTween.p0, camTween.p1, k);
    controls.target.lerpVectors(camTween.t0, camTween.t1, k);
    if (t >= 1) camTween = null;
    busy = true;
  }
  if (controls.update()) busy = true;

  // Keep the camera over the board.
  const lim = span * .6;
  const tx = clamp(controls.target.x, box.min.x - 1, box.max.x + 1) - controls.target.x;
  const tz = clamp(controls.target.z, box.min.z - 1, box.max.z + 1) - controls.target.z;
  if (loaded && (Math.abs(tx) > 1e-4 || Math.abs(tz) > 1e-4) && lim > 0) {
    controls.target.x += tx; controls.target.z += tz;
    camera.position.x += tx; camera.position.z += tz;
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
    govern(now);
    renderer.render(scene, camera);
    if (dirty > 0) dirty--;
    if (busy) dirty = Math.max(dirty, 1);
  }
  if (shake) camera.position.sub(shake);
}

/* Frame-time governor: while frames render back to back, lower the resolution when they run
   long (slow phone, busy browser) and raise it again when there's headroom. */
let govLast = 0, govSum = 0, govN = 0;
function govern(now) {
  const dt = now - govLast;
  govLast = now;
  if (dt <= 0 || dt > 100) return; // first frame after idle: not a measurement
  govSum += dt; govN++;
  if (govN < 45) return;
  const avg = govSum / govN;
  govSum = govN = 0;
  let next = prNow;
  if (avg > 21) next = Math.max(.6, prNow * .85);
  else if (avg < 14 && prNow < prMax) next = Math.min(prMax, prNow * 1.1);
  if (Math.abs(next - prNow) > .01) {
    prNow = next;
    renderer.setPixelRatio(prNow);
    renderer.setSize(innerWidth, innerHeight);
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
    case 'cam':
      if (!loaded) break;
      if (m.op === 'fit') { const h = homeView(); tweenTo(h.pos, h.target, m.ms ?? 380); }
      else if (m.op === 'zoom') zoom(m.k || 1.25);
      else if (m.op === 'push') pushIn(m.a, m.b, m.ms ?? 650);
      else if (m.op === 'pull') pullBack(m.ms ?? 650);
      break;
  }
}
window.board = { receive, stats: () => ({ calls: renderer.info.render.calls, triangles: renderer.info.render.triangles, pixelRatio: prNow }) };
if (window.chrome && window.chrome.webview) window.chrome.webview.addEventListener('message', e => receive(e.data));
window.addEventListener('message', e => {
  if (typeof e.data === 'string' && e.data.startsWith('board3d:')) return; // our own posts (no parent)
  if (e.source === window.parent && window.parent !== window) receive(e.data);
});
post({ t: 'loaded' });
