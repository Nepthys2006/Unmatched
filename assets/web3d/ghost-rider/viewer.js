/* Ghost Rider viewer: shows the three models from model.js on a turntable with bloom.
   Views (also the URL hash): #rider, #cycle, #riding. */
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { createRider, createHellCycle, createRidingGhostRider } from './model.js';

const host = document.getElementById('stage');
const status = document.getElementById('status');
const caption = document.getElementById('caption');
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

let renderer;
try {
  renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
} catch (e) {
  status.textContent = 'This browser cannot draw WebGL, so the 3D model cannot be shown';
  throw e;
}
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
host.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0a0807);
scene.fog = new THREE.Fog(0x0a0807, 5, 14);
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), .04).texture;
scene.environmentIntensity = .22;

const camera = new THREE.PerspectiveCamera(32, innerWidth / innerHeight, .05, 80);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = .08;
controls.minDistance = .9;
controls.maxDistance = 10;
controls.maxPolarAngle = Math.PI * .495;
controls.autoRotateSpeed = .7;
controls.autoRotate = !reduceMotion;

/* lights: warm key with shadows, cold blue rim from behind, low orange fill */
scene.add(new THREE.HemisphereLight(0x8a8494, 0x1a0d06, .3));
const key = new THREE.DirectionalLight(0xffe4c8, 2.1);
key.position.set(2.6, 4.6, 3.4);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
Object.assign(key.shadow.camera, { left: -2.6, right: 2.6, top: 2.6, bottom: -1.2, near: .5, far: 14 });
key.shadow.bias = -.0004;
key.shadow.normalBias = .02;
scene.add(key);
const rim = new THREE.DirectionalLight(0x7f9fff, 1.5);
rim.position.set(-3, 2.6, -3.6);
scene.add(rim);
const fill = new THREE.DirectionalLight(0xff8a3a, .45);
fill.position.set(-2.5, .8, 2.5);
scene.add(fill);

/* floor: scorched concrete with a soft edge */
function floorTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 512;
  const g = c.getContext('2d');
  const rg = g.createRadialGradient(256, 256, 30, 256, 256, 256);
  rg.addColorStop(0, '#1c1714'); rg.addColorStop(.35, '#120f0d'); rg.addColorStop(1, '#0a0807');
  g.fillStyle = rg;
  g.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 4000; i++) {
    const v = Math.random() * 40 | 0;
    g.fillStyle = `rgba(${v},${v * .8 | 0},${v * .7 | 0},.25)`;
    g.fillRect(Math.random() * 512, Math.random() * 512, 2, 2);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const floor = new THREE.Mesh(new THREE.CircleGeometry(14, 96), new THREE.MeshStandardMaterial({ map: floorTexture(), roughness: .92, metalness: 0 }));
floor.rotation.x = -Math.PI / 2;
floor.receiveShadow = true;
scene.add(floor);

/* road for the riding view: asphalt with dashed lane lines, scrolled to fake speed */
function roadTexture() {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 512;
  const g = c.getContext('2d');
  g.fillStyle = '#16130f';
  g.fillRect(0, 0, 256, 512);
  for (let i = 0; i < 9000; i++) {
    const v = 14 + Math.random() * 34 | 0;
    g.fillStyle = `rgb(${v},${v * .92 | 0},${v * .85 | 0})`;
    g.fillRect(Math.random() * 256, Math.random() * 512, 1.6, 1.6);
  }
  g.fillStyle = 'rgba(214,190,120,.55)';
  for (const y of [40, 472]) g.fillRect(0, y - 5, 150, 10);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(16, 1);
  t.anisotropy = 8;
  return t;
}
const roadTex = roadTexture();
const road = new THREE.Mesh(new THREE.PlaneGeometry(48, 4.4), new THREE.MeshStandardMaterial({ map: roadTex, roughness: .88 }));
road.rotation.x = -Math.PI / 2;
road.position.y = .002;
road.receiveShadow = true;

/* post: bloom on everything brighter than white (the fire, eyes, lamps) */
const composer = new EffectComposer(renderer);
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), .6, .35, 1);
composer.addPass(bloom);
composer.addPass(new OutputPass());
let glow = true;

/* ---- the three stages, built the first time they are shown */
const STAGES = {
  rider: {
    caption: 'The rider, on foot',
    target: [0, .92, 0], cam: [1.9, 1.5, 4.4],
    build() {
      const g = new THREE.Group();
      const stance = createRider({ pose: 'stance' });
      const tpose = createRider({ pose: 'tpose' });
      tpose.visible = false;
      g.add(stance, tpose);
      return { group: g, update: t => (stance.visible ? stance : tpose).userData.update(t), stance, tpose };
    },
  },
  cycle: {
    caption: 'The Hell Cycle',
    target: [0, .55, 0], cam: [2.6, 1.35, 3.6],
    build() {
      const bike = createHellCycle();
      bike.rotation.x = -.04;   // resting on the kickstand
      return { group: bike, update: t => bike.userData.update(t) };
    },
  },
  riding: {
    caption: 'Riding, everything on fire',
    target: [-.1, .78, 0], cam: [3.2, 1.6, 4.3],
    build() {
      const g = new THREE.Group();
      const ride = createRidingGhostRider();
      g.add(ride, road);
      return { group: g, update: (t, dt, o) => { ride.userData.update(t, o); roadTex.offset.x += dt * ride.userData.speed() * 9 / 3; }, ride };
    },
  },
};
const built = {};
let view = null, throttle = 1;

function show(name, { snap = true } = {}) {
  if (!STAGES[name]) name = 'rider';
  if (name === view) return;
  view = name;
  if (!built[name]) {
    built[name] = STAGES[name].build();
    scene.add(built[name].group);
  }
  for (const [k, s] of Object.entries(built)) s.group.visible = k === name;
  floor.visible = name !== 'riding';
  const st = STAGES[name];
  if (snap) {
    controls.target.set(...st.target);
    camera.position.set(...st.cam);
    const fit = Math.max(1, .8 / camera.aspect);   // back off on tall, narrow screens
    camera.position.sub(controls.target).multiplyScalar(fit).add(controls.target);
    controls.update();
  }
  caption.textContent = st.caption;
  for (const b of document.querySelectorAll('.views button')) b.setAttribute('aria-selected', String(b.dataset.view === name));
  for (const el of document.querySelectorAll('[data-for]')) el.hidden = el.dataset.for !== name;
  if (location.hash !== '#' + name) history.replaceState(null, '', '#' + name);
}

function press(group, btn) {
  for (const b of group.querySelectorAll('button')) b.setAttribute('aria-pressed', String(b === btn));
}

document.querySelector('.views').addEventListener('click', e => {
  const b = e.target.closest('button[data-view]');
  if (b) show(b.dataset.view);
});
document.querySelector('[data-for="rider"]').addEventListener('click', e => {
  const b = e.target.closest('button[data-pose]');
  if (!b) return;
  press(e.currentTarget, b);
  const r = built.rider;
  r.stance.visible = b.dataset.pose === 'stance';
  r.tpose.visible = !r.stance.visible;
});
document.querySelector('[data-for="riding"]').addEventListener('click', e => {
  const b = e.target.closest('button[data-throttle]');
  if (!b) return;
  press(e.currentTarget, b);
  throttle = +b.dataset.throttle;
});
for (const b of document.querySelectorAll('[data-toggle]')) {
  if (b.dataset.toggle === 'spin') b.setAttribute('aria-pressed', String(controls.autoRotate));
  b.addEventListener('click', () => {
    const on = b.getAttribute('aria-pressed') !== 'true';
    b.setAttribute('aria-pressed', String(on));
    if (b.dataset.toggle === 'spin') controls.autoRotate = on;
    else glow = on;
  });
}
addEventListener('hashchange', () => show(location.hash.slice(1)));

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  composer.setSize(innerWidth, innerHeight);
});

const clock = new THREE.Clock();
let elapsed = 0;
function frame() {
  const dt = Math.min(clock.getDelta(), .1);
  elapsed += dt;
  controls.update(dt);
  scene.updateMatrixWorld();
  built[view].update(elapsed, dt, { throttle });
  if (glow) composer.render(dt);
  else renderer.render(scene, camera);
}

show(location.hash.slice(1) || 'rider');
status.hidden = true;
renderer.setAnimationLoop(frame);
window.__ghostRider = { fires: on => scene.traverse(o => { if (o.isFire) o.visible = on; }), show, scene, camera, controls, renderer, built, setTime: t => { elapsed = t; }, frame };
