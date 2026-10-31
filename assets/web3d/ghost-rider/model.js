/* Ghost Rider: procedural Three.js models built from the character sheet.

     createRider({pose})        the rider on foot. pose 'tpose' is the sheet's reference pose,
                                'stance' has him holding a burning chain whip.
     createHellCycle()          the bike on its own: flaming wheels, blue exhaust jets.
     createRidingGhostRider()   the rider on the bike with everything on fire.

   Each returns a THREE.Group. Call group.userData.update(time, {throttle}) every frame to animate the
   fire (and, when riding, the wheels and the wind). Units are metres. The figures stand on y = 0.
   The rider faces +Z and the bike points +X. Pass {fire: false} to get just the meshes (that is how
   the .glb files are exported).

   Fire is a GPU particle system (class Fire): instanced quads moved entirely in the vertex shader and
   drawn with additive blending. Its colours go above 1, so a bloom pass makes them glow. */
import * as THREE from 'three';

const V3 = THREE.Vector3;
const TAU = Math.PI * 2;
const clamp = THREE.MathUtils.clamp;
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const ZERO = new V3();

export function rng(seed = 1) {
  return () => {
    seed = seed + 0x6D2B79F5 | 0;
    let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

/* Smooth curve through [[x, y], ...] keys (cubic Hermite with finite-difference tangents). */
function spline(keys) {
  const n = keys.length;
  const m = keys.map((k, i) => {
    const a = keys[Math.max(0, i - 1)], b = keys[Math.min(n - 1, i + 1)];
    return (b[1] - a[1]) / ((b[0] - a[0]) || 1);
  });
  return x => {
    if (x <= keys[0][0]) return keys[0][1];
    if (x >= keys[n - 1][0]) return keys[n - 1][1];
    let i = 1;
    while (keys[i][0] < x) i++;
    const [x0, y0] = keys[i - 1], [x1, y1] = keys[i], h = x1 - x0, t = (x - x0) / h, t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m[i - 1] + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m[i];
  };
}

/* ---------------------------------------------------------------- geometry helpers */

/* Moves every vertex through fn, then rebuilds smooth normals (welded across UV seams). */
function sculpt(geo, fn) {
  const p = geo.attributes.position, v = new V3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    fn(v, i);
    p.setXYZ(i, v.x, v.y, v.z);
  }
  p.needsUpdate = true;
  geo.computeVertexNormals();
  weldNormals(geo);
  geo.computeBoundingBox();
  geo.computeBoundingSphere();
  return geo;
}

function weldNormals(geo) {
  const p = geo.attributes.position, n = geo.attributes.normal, sums = new Map();
  const key = i => `${Math.round(p.getX(i) * 1e5)},${Math.round(p.getY(i) * 1e5)},${Math.round(p.getZ(i) * 1e5)}`;
  const keys = new Array(p.count);
  for (let i = 0; i < p.count; i++) {
    const k = keys[i] = key(i);
    let s = sums.get(k);
    if (!s) sums.set(k, s = new V3());
    s.x += n.getX(i); s.y += n.getY(i); s.z += n.getZ(i);
  }
  for (let i = 0; i < p.count; i++) {
    const s = sums.get(keys[i]), l = s.length() || 1;
    n.setXYZ(i, s.x / l, s.y / l, s.z / l);
  }
}

function roundedBox(w, h, d, r, seg = 5) {
  const g = new THREE.BoxGeometry(w, h, d, seg, seg, seg);
  const hx = w / 2 - r, hy = h / 2 - r, hz = d / 2 - r, inner = new V3(), dir = new V3();
  return sculpt(g, p => {
    inner.set(clamp(p.x, -hx, hx), clamp(p.y, -hy, hy), clamp(p.z, -hz, hz));
    dir.subVectors(p, inner);
    if (dir.lengthSq() > 1e-14) p.copy(inner).addScaledVector(dir.normalize(), r);
  });
}

/* A tapered limb hanging down from its joint: keys are [[t along the length (0..1), radius], ...]. */
function limbGeo(len, keys, { seg = 28, rows = 22, sx = 1, sz = 1 } = {}) {
  const r = spline(keys);
  return sculpt(new THREE.CylinderGeometry(1, 1, 1, seg, rows, true), p => {
    const t = .5 - p.y, rad = r(t);
    p.set(p.x * rad * sx, -t * len, p.z * rad * sz);
  });
}

const sphere = (r, w = 24, h = 16) => new THREE.SphereGeometry(r, w, h);
const capsule = (r, len) => new THREE.CapsuleGeometry(r, Math.max(.001, len - 2 * r), 4, 10);

function add(parent, geo, mat, pos, rot, scl) {
  const m = new THREE.Mesh(geo, mat);
  if (pos) m.position.set(pos[0], pos[1], pos[2]);
  if (rot) m.rotation.set(rot[0], rot[1], rot[2]);
  if (scl !== undefined && scl !== null) typeof scl === 'number' ? m.scale.setScalar(scl) : m.scale.set(scl[0], scl[1], scl[2]);
  m.castShadow = true;
  m.receiveShadow = true;
  parent.add(m);
  return m;
}

function joint(parent, name, pos) {
  const g = new THREE.Group();
  g.name = name;
  g.position.set(pos[0], pos[1], pos[2]);
  parent.add(g);
  return g;
}

const _yAxis = new V3(0, 1, 0);
/* A cylinder from a to b (world-of-parent coordinates). */
function rod(parent, a, b, r, mat, radial = 12, r2 = r) {
  const A = new V3(...a), B = new V3(...b), d = B.clone().sub(A), len = d.length();
  const m = add(parent, new THREE.CylinderGeometry(r2, r, len, radial, 1), mat);
  m.position.copy(A).addScaledVector(d, .5);
  m.quaternion.setFromUnitVectors(_yAxis, d.normalize());
  return m;
}

function tube(parent, pts, r, mat, { segs = 64, radial = 12, closed = false, tension } = {}) {
  const curve = new THREE.CatmullRomCurve3(pts.map(p => p.isVector3 ? p : new V3(...p)), closed, tension === undefined ? 'centripetal' : 'catmullrom', tension);
  const m = add(parent, new THREE.TubeGeometry(curve, segs, r, radial, closed), mat);
  m.userData.curve = curve;
  return m;
}

/* Chain links along a curve. normalAt(u, point, out) can steer which way the links lie. */
function chain(curve, mat, { k = 1, normalAt } = {}) {
  const R = .009 * k, r = .0029 * k, sy = 1.5;
  const geo = new THREE.TorusGeometry(R, r, 6, 14);
  geo.scale(1, sy, 1);
  const pitch = 2 * (R - r) * sy * 1.04;
  const n = Math.max(2, Math.floor(curve.getLength() / pitch));
  const im = new THREE.InstancedMesh(geo, mat, n);
  const m = new THREE.Matrix4(), t = new V3(), p = new V3(), a = new V3(), b = new V3();
  for (let i = 0; i < n; i++) {
    const u = (i + .5) / n;
    curve.getPointAt(u, p);
    curve.getTangentAt(u, t);
    if (normalAt) normalAt(u, p, a); else a.set(0, 1, 0);
    a.addScaledVector(t, -a.dot(t));
    if (a.lengthSq() < 1e-8) a.set(1, 0, 0).addScaledVector(t, -t.x);
    a.normalize();
    if (i & 1) a.cross(t).normalize();
    b.crossVectors(t, a);
    m.makeBasis(b, t, a).setPosition(p);
    im.setMatrixAt(i, m);
  }
  im.castShadow = im.receiveShadow = true;
  im.userData.curve = curve;
  return im;
}

/* ---------------------------------------------------------------- textures and materials */

function canvas(w, h, draw) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  return c;
}

function tex(c, { srgb = false, rx = 1, ry = 1 } = {}) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(rx, ry);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

function leatherGrain() {
  return canvas(512, 512, (g, w, h) => {
    const r = rng(11);
    g.fillStyle = '#808080';
    g.fillRect(0, 0, w, h);
    for (let i = 0; i < 9000; i++) {
      const v = 95 + r() * 75 | 0;
      g.fillStyle = `rgba(${v},${v},${v},.55)`;
      g.beginPath(); g.arc(r() * w, r() * h, 1 + r() * 3.2, 0, TAU); g.fill();
    }
    g.lineCap = 'round';
    for (let i = 0; i < 80; i++) {
      let x = r() * w, y = r() * h, a = r() * TAU;
      g.strokeStyle = `rgba(30,30,30,${.25 + r() * .35})`;
      g.lineWidth = .6 + r() * 1.8;
      g.beginPath(); g.moveTo(x, y);
      for (let k = 0; k < 6; k++) { a += (r() - .5) * .8; x += Math.cos(a) * 14; y += Math.sin(a) * 14; g.lineTo(x, y); }
      g.stroke();
    }
  });
}

/* Glowing cracks for the burning tyres (emissive map). */
function lavaCracks() {
  return canvas(1024, 128, (g, w, h) => {
    const r = rng(5);
    g.fillStyle = '#000';
    g.fillRect(0, 0, w, h);
    g.lineCap = g.lineJoin = 'round';
    for (let i = 0; i < 90; i++) {
      let x = r() * w, y = r() * h, a = r() * TAU;
      const pts = [[x, y]], n = 3 + r() * 6 | 0;
      for (let k = 0; k < n; k++) { a += (r() - .5) * 1.6; x += Math.cos(a) * (10 + r() * 26); y += Math.sin(a) * (6 + r() * 10); pts.push([x, y]); }
      const stroke = (color, width, blur) => {
        g.strokeStyle = color; g.lineWidth = width; g.shadowColor = '#ff5000'; g.shadowBlur = blur;
        g.beginPath(); g.moveTo(...pts[0]); for (const p of pts) g.lineTo(...p); g.stroke();
      };
      stroke('#ff5a00', 3 + r() * 3, 14);
      stroke('#ffd27a', 1 + r(), 3);
    }
  });
}

/* Black paint with blue flames licking back from the front of the tank (sphere UVs: u = .5 is the nose). */
function tankDecal() {
  return canvas(1024, 512, (g, w, h) => {
    g.fillStyle = '#0c0d10';
    g.fillRect(0, 0, w, h);
    const r = rng(23);
    const side = (x0, dir) => {
      for (let i = 0; i < 8; i++) {
        const y = h * (.36 + r() * .24), len = w * (.14 + r() * .22), th = h * (.025 + r() * .045);
        const grad = g.createLinearGradient(x0, 0, x0 + dir * len, 0);
        grad.addColorStop(0, '#0a36ff'); grad.addColorStop(.55, '#2f8cff'); grad.addColorStop(1, 'rgba(140,210,255,0)');
        g.fillStyle = grad;
        g.beginPath();
        g.moveTo(x0, y - th);
        g.bezierCurveTo(x0 + dir * len * .4, y - th * 1.7, x0 + dir * len * .7, y - th * (.2 + r()), x0 + dir * len, y - th * 1.4 * (r() - .3));
        g.bezierCurveTo(x0 + dir * len * .6, y + th * .5, x0 + dir * len * .3, y + th * 1.3, x0, y + th);
        g.closePath();
        g.fill();
      }
    };
    side(w * .47, -1);
    side(w * .53, 1);
  });
}

function glowStreak() {
  return canvas(512, 64, (g, w, h) => {
    const lg = g.createLinearGradient(0, 0, w, 0);
    lg.addColorStop(0, 'rgba(255,255,255,1)'); lg.addColorStop(.25, 'rgba(255,255,255,.55)'); lg.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = lg;
    g.fillRect(0, 0, w, h);
    g.globalCompositeOperation = 'destination-in';
    const vg = g.createLinearGradient(0, 0, 0, h);
    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(.5, 'rgba(0,0,0,1)'); vg.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = vg;
    g.fillRect(0, 0, w, h);
  });
}

let MATS = null;
export function materials() {
  if (MATS) return MATS;
  const grain = tex(leatherGrain(), { rx: 3, ry: 3 });
  const lava = tex(lavaCracks(), { srgb: true, rx: 2, ry: 1 });
  const decal = tex(tankDecal(), { srgb: true });
  const leather = (color, roughness, clearcoat, bump = 1.4) => new THREE.MeshPhysicalMaterial({
    color, roughness, metalness: 0, clearcoat: clearcoat * .5, clearcoatRoughness: .45,
    sheen: .25, sheenRoughness: .6, sheenColor: new THREE.Color(0x2c2c30), bumpMap: grain, bumpScale: bump,
  });
  MATS = {
    jacket: leather(0x141416, .42, .6, .7),
    pants: leather(0x111112, .5, .35, .8),
    boot: leather(0x0c0c0d, .28, .85, .8),
    glove: leather(0x121214, .38, .6, .6),
    seat: leather(0x0f0e0e, .45, .5),
    lining: new THREE.MeshStandardMaterial({ color: 0x0a0a0b, roughness: .9, side: THREE.DoubleSide }),
    bone: new THREE.MeshPhysicalMaterial({
      color: 0xb98543, roughness: .48, metalness: .28, clearcoat: .2, clearcoatRoughness: .5,
      emissive: 0xff4a10, emissiveIntensity: .04, bumpMap: grain, bumpScale: .35,
    }),
    teeth: new THREE.MeshPhysicalMaterial({ color: 0xcdb07a, roughness: .35, metalness: .1, clearcoat: .4, emissive: 0xff5a10, emissiveIntensity: .03 }),
    socket: new THREE.MeshBasicMaterial({ color: 0x070301 }),
    skull: null,
    eye: new THREE.MeshBasicMaterial({ color: new THREE.Color(7, 2.8, .45) }),
    chrome: new THREE.MeshStandardMaterial({ color: 0xd0d3d8, metalness: 1, roughness: .2, envMapIntensity: .7 }),
    steel: new THREE.MeshStandardMaterial({ color: 0x8c8f95, metalness: 1, roughness: .3 }),
    chain: new THREE.MeshStandardMaterial({ color: 0x5c5e63, metalness: 1, roughness: .34 }),
    blackMetal: new THREE.MeshPhysicalMaterial({ color: 0x1a1b1e, metalness: .8, roughness: .36, clearcoat: .5, clearcoatRoughness: .25 }),
    darkMetal: new THREE.MeshStandardMaterial({ color: 0x2a2b2f, metalness: .9, roughness: .45 }),
    paint: new THREE.MeshPhysicalMaterial({
      color: 0xffffff, map: decal, metalness: .5, roughness: .28, clearcoat: 1, clearcoatRoughness: .08,
      emissive: 0x6fb4ff, emissiveMap: decal, emissiveIntensity: .55,
    }),
    rubber: new THREE.MeshStandardMaterial({ color: 0x0d0d0d, roughness: .85 }),
    tire: new THREE.MeshStandardMaterial({ color: 0x0e0b09, roughness: .75, emissive: 0xffffff, emissiveMap: lava, emissiveIntensity: 1.8 }),
    lens: new THREE.MeshBasicMaterial({ color: new THREE.Color(5, 4, 2.2) }),
    tail: new THREE.MeshBasicMaterial({ color: new THREE.Color(6, .25, .1) }),
    blueGlow: new THREE.MeshBasicMaterial({ color: new THREE.Color(.5, 1.6, 7) }),
    streak: new THREE.MeshBasicMaterial({
      map: tex(glowStreak()), color: new THREE.Color(3, 1, .2), transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending, opacity: 0,
    }),
  };
  MATS.jacketTwoSided = MATS.jacket.clone();
  MATS.jacketTwoSided.side = THREE.DoubleSide;
  MATS.skull = MATS.bone.clone();
  MATS.skull.vertexColors = true;
  MATS.streak.map.wrapS = MATS.streak.map.wrapT = THREE.ClampToEdgeWrapping;
  return MATS;
}

/* ---------------------------------------------------------------- fire */

const FIRE_VS = /* glsl */`
uniform float uTime, uLife, uRise, uSpread, uTurb, uStretch, uSize0, uSize1;
uniform vec3 uUp, uWind;
attribute vec3 aOrigin, aNormal;
attribute vec4 aSeed;
varying vec2 vUv;
varying float vT, vSeed;
void main() {
  float life = uLife * (.65 + .7 * aSeed.y);
  float t = fract(uTime / life + aSeed.x);
  float ph = aSeed.w * 6.2831;
  vec3 sway = vec3(sin(uTime * 3.7 + ph + t * 6.), .5 * sin(uTime * 2.3 + ph * 2.), cos(uTime * 3.1 + ph * 1.7 + t * 5.));
  vec3 p = aOrigin + aNormal * (uSpread * t) + uUp * (uRise * t * (.7 + .6 * aSeed.z)) + uWind * (t * t) + sway * (uTurb * t);
  vec3 vel = aNormal * uSpread + uUp * uRise + uWind * (2. * t) + sway * (uTurb * .4);
  vec4 mv = modelViewMatrix * vec4(p, 1.);
  vec3 vv = (modelViewMatrix * vec4(vel, 0.)).xyz;
  float l = length(vv.xy);
  vec2 ax = l > 1e-5 ? vv.xy / l : vec2(0., 1.);
  vec2 rt = vec2(ax.y, -ax.x);
  float size = mix(uSize0, uSize1, t) * (.55 + .9 * aSeed.z) * smoothstep(0., .15, t);
  float st = 1. + (uStretch - 1.) * clamp(l / (length(vv) + 1e-5), 0., 1.);
  mv.xy += (rt * position.x + ax * position.y * st) * size;
  vUv = position.xy;
  vT = t;
  vSeed = aSeed.w;
  gl_Position = projectionMatrix * mv;
}`;

const FIRE_FS = /* glsl */`
uniform vec3 uC0, uC1, uC2;
uniform float uIntensity, uTime;
varying vec2 vUv;
varying float vT, vSeed;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3. - 2. * f);
  return mix(mix(hash(i), hash(i + vec2(1., 0.)), f.x), mix(hash(i + vec2(0., 1.)), hash(i + vec2(1., 1.)), f.x), f.y);
}
void main() {
  vec2 q = vUv;
  q.x *= 1. + max(q.y, 0.) * 1.1;
  q.y *= q.y > 0. ? .9 : 1.3;
  float d = length(q);
  float a = 1. - smoothstep(0., 1., d);
  a *= a;
  float flick = .8 + .2 * sin(uTime * 23. + vSeed * 50.);
  float n = vnoise(vUv * 1.7 + vec2(vSeed * 17., vSeed * 5. - uTime * 2.6));
  a *= .35 + n;
  float fade = smoothstep(0., .2, vT) * (1. - vT) * (1. - vT);
  vec3 c = vT < .3 ? mix(uC0, uC1, vT / .3) : mix(uC1, uC2, (vT - .3) / .7);
  float alpha = a * fade * flick;
  if (alpha < .002) discard;
  gl_FragColor = vec4(c * uIntensity, alpha);
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
}`;

export const PALETTES = {
  fire: [[2.6, 1.5, .4], [2.4, .62, .06], [.75, .07, .01]],
  blue: [[1.8, 2.8, 4.2], [.2, .6, 3.4], [.02, .06, .8]],
  ember: [[5, 3, 1], [3.5, 1, .1], [1.4, .2, 0]],
};

/* Every Fire's intensity is scaled by this: many additive quads overlap, so each one is faint. */
export const FIRE_GAIN = .11;

const _m4 = new THREE.Matrix4(), _m3 = new THREE.Matrix3();

/* o: {count, emit(rand, outPos, outDir, i), size: [start, end], life, rise, spread, turb, stretch,
       palette, intensity, windScale, seed}. Positions are in the fire's own space; rise and wind are
       given in world space and converted every frame, so fire still burns upward on a moving rig. */
export class Fire extends THREE.Mesh {
  constructor(o) {
    const n = o.count;
    const geo = new THREE.InstancedBufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0], 3));
    geo.setIndex([0, 1, 2, 0, 2, 3]);
    const org = new Float32Array(n * 3), dir = new Float32Array(n * 3), seed = new Float32Array(n * 4);
    const r = rng(o.seed || 7), p = new V3(), d = new V3();
    for (let i = 0; i < n; i++) {
      p.set(0, 0, 0); d.set(0, 1, 0);
      o.emit(r, p, d, i);
      org[i * 3] = p.x; org[i * 3 + 1] = p.y; org[i * 3 + 2] = p.z;
      dir[i * 3] = d.x; dir[i * 3 + 1] = d.y; dir[i * 3 + 2] = d.z;
      for (let k = 0; k < 4; k++) seed[i * 4 + k] = r();
    }
    geo.setAttribute('aOrigin', new THREE.InstancedBufferAttribute(org, 3));
    geo.setAttribute('aNormal', new THREE.InstancedBufferAttribute(dir, 3));
    geo.setAttribute('aSeed', new THREE.InstancedBufferAttribute(seed, 4));
    geo.instanceCount = n;
    const pal = PALETTES[o.palette || 'fire'];
    const size = o.size || [.05, .02];
    const mat = new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 }, uLife: { value: o.life || .7 }, uRise: { value: o.rise ?? .3 },
        uSpread: { value: o.spread ?? .05 }, uTurb: { value: o.turb ?? .03 }, uStretch: { value: o.stretch ?? 1.6 },
        uSize0: { value: size[0] }, uSize1: { value: size[1] },
        uUp: { value: new V3(0, 1, 0) }, uWind: { value: new V3() },
        uC0: { value: new V3(...pal[0]) }, uC1: { value: new V3(...pal[1]) }, uC2: { value: new V3(...pal[2]) },
        uIntensity: { value: (o.intensity ?? 1) * FIRE_GAIN },
      },
      vertexShader: FIRE_VS,
      fragmentShader: FIRE_FS,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    super(geo, mat);
    this.isFire = true;
    this.frustumCulled = false;
    this.renderOrder = 10;
    this.windScale = o.windScale ?? 1;
    this.baseIntensity = o.intensity ?? 1;
  }

  update(time, wind = ZERO) {
    const u = this.material.uniforms;
    u.uTime.value = time;
    _m3.setFromMatrix4(_m4.copy(this.matrixWorld).invert());
    u.uUp.value.set(0, 1, 0).applyMatrix3(_m3);
    u.uWind.value.copy(wind).multiplyScalar(this.windScale).applyMatrix3(_m3);
  }
}

export class FireLight extends THREE.PointLight {
  constructor(color, intensity, distance, seed = 0) {
    super(color, intensity, distance, 2);
    this.isFireLight = true;
    this.base = intensity;
    this.seed = seed;
  }
  update(t) {
    this.intensity = this.base * (.82 + .12 * Math.sin(t * 13 + this.seed) + .08 * Math.sin(t * 29.7 + this.seed * 3));
  }
}

/* Returns update(time, wind): animates every Fire and FireLight under group (collected on first use). */
function fireAnimator(group) {
  let fires = null, lights = null;
  return (t, wind = ZERO) => {
    if (!fires) {
      fires = []; lights = [];
      group.traverse(o => { if (o.isFire) fires.push(o); else if (o.isFireLight) lights.push(o); });
    }
    for (const f of fires) f.update(t, wind);
    for (const l of lights) l.update(t);
  };
}

const randDir = (r, out) => {
  do out.set(r() * 2 - 1, r() * 2 - 1, r() * 2 - 1); while (out.lengthSq() > 1 || out.lengthSq() < .01);
  return out.normalize();
};

/* ---------------------------------------------------------------- the rider */

const TORSO_Y0 = -.08, TORSO_Y1 = .5;   // jacket hem and neck line, in spine space
const torsoW = spline([[0, .176], [.12, .166], [.35, .168], [.6, .19], [.78, .208], [.88, .206], [.95, .176], [1, .074]]);
const torsoD = spline([[0, .126], [.12, .116], [.35, .118], [.6, .13], [.78, .126], [.88, .112], [.95, .094], [1, .064]]);
const SUPER = 2.8;   // superellipse exponent of the torso's cross-section (2 = an ellipse)

/* A point on the jacket: h runs hem (0) to neck (1), a is the angle round the body (0 = front). */
function torsoPoint(h, a, off = 0, out = new V3()) {
  const w = torsoW(h) + off, d = torsoD(h) + off, s = Math.sin(a), c = Math.cos(a), k = 2 / SUPER;
  const x = Math.sign(s) * Math.pow(Math.abs(s), k) * w;
  let z = Math.sign(c) * Math.pow(Math.abs(c), k) * d;
  if (c > 0) z += c * c * .012 * Math.exp(-(((h - .66) / .14) ** 2));
  else z -= c * c * .007 * Math.exp(-(((h - .76) / .12) ** 2));
  return out.set(x, TORSO_Y0 + h * (TORSO_Y1 - TORSO_Y0), z);
}

const torsoH = y => (y - TORSO_Y0) / (TORSO_Y1 - TORSO_Y0);
/* The front-facing angle whose surface point sits at x. */
function torsoAngle(h, x) {
  const s = clamp(Math.abs(x) / torsoW(h), 0, 1);
  return Math.sign(x) * Math.asin(Math.pow(s, SUPER / 2));
}

/* Wraps flat front details (x, y in spine space, z = height off the surface) onto the jacket. */
function conformFront(geo, off) {
  return sculpt(geo, p => {
    const h = torsoH(p.y);
    torsoPoint(h, torsoAngle(h, p.x), off + p.z, p);
  });
}

function skullGeometry() {
  // hollows (sockets, nose, temples) are darkened through vertex colours so the face reads at a distance
  let hollow = 0;
  const dent = (p, c, r, depth, dir, isHollow = false) => {
    const dx = (p.x - c[0]) / r[0], dy = (p.y - c[1]) / r[1], dz = (p.z - c[2]) / r[2], d2 = dx * dx + dy * dy + dz * dz;
    if (d2 < 1) {
      const f = 1 - d2, k = depth * f * f;
      p.addScaledVector(dir, k);
      if (isHollow) hollow += k;
    }
  };
  const n = new V3(), geo = new THREE.SphereGeometry(1, 96, 72), col = new Float32Array(geo.attributes.position.count * 3);
  sculpt(geo, (p, i) => {
    n.copy(p);
    hollow = 0;
    const front = smooth(.05, .75, n.z), low = smooth(.25, -.75, n.y), face = front * low;
    let x = n.x * .07, y = n.y * .072, z = n.z * .09;
    if (n.y < 0) y *= .85;
    x *= 1 - face * .3 - smooth(-.2, -.9, n.y) * .12;
    y -= face * .028;
    z += face * .004;
    z -= (1 - front) * smooth(.2, -.6, n.y) * .012;
    p.set(x, y, z);
    for (const s of [-1, 1]) {
      dent(p, [s * .03, .015, .086], [.03, .011, .03], .005, new V3(0, .3, 1).normalize());                   // brow ridge
      dent(p, [s * .03, -.009, .088], [.026, .023, .045], .027, new V3(-s * .25, .05, -1).normalize(), true); // eye socket
      dent(p, [s * .05, -.036, .062], [.026, .016, .03], .008, new V3(s, -.2, .6).normalize());                // cheek bone
      dent(p, [s * .069, .0, .03], [.03, .03, .035], .007, new V3(-s, 0, 0), true);                            // temple
    }
    const nr = .007 + .008 * smooth(-.028, -.056, p.y);   // nasal opening: an upside-down heart
    dent(p, [0, -.042, .09], [nr, .017, .04], .02, new V3(0, 0, -1), true);
    const c = (1 - clamp(hollow / .016, 0, 1) * .8) * (.62 + .38 * smooth(-.9, .3, n.y));
    col[i * 3] = c; col[i * 3 + 1] = c * .95; col[i * 3 + 2] = c * .9;
  });
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  return geo;
}

function buildSkull(head, M) {
  const skull = joint(head, 'skull', [0, .112, .014]);
  skull.scale.setScalar(1.08);
  add(skull, skullGeometry(), M.skull);
  // mandible: a U-shaped plate (shape x is vertical here: the extrude frames put the normal along y)
  const body = new THREE.CatmullRomCurve3([[-.047, -.1, -.008], [-.042, -.104, .042], [0, -.107, .074], [.042, -.104, .042], [.047, -.1, -.008]].map(a => new V3(...a)));
  const sh = new THREE.Shape();
  sh.moveTo(-.011, -.0045); sh.lineTo(.008, -.004); sh.quadraticCurveTo(.01, 0, .008, .004); sh.lineTo(-.011, .0045); sh.quadraticCurveTo(-.013, 0, -.011, -.0045);
  const jaw = new THREE.ExtrudeGeometry(sh, { steps: 40, bevelEnabled: false, extrudePath: body, curveSegments: 4 });
  jaw.computeVertexNormals();
  add(skull, jaw, M.bone);
  add(skull, sphere(1, 20, 12), M.bone, [0, -.111, .072], null, [.018, .009, .008]);
  // teeth
  const tooth = roundedBox(.0072, .016, .0066, .0026, 2);
  const row = (y, rx, rz, cz, n, h) => {
    for (let i = 0; i < n; i++) {
      const f = (i + .5) / n * 2 - 1, phi = f * 1.2;
      const m = add(skull, tooth, M.teeth, [rx * Math.sin(phi), y, cz + rz * Math.cos(phi)], [0, phi, 0], [1 - Math.abs(f) * .15, h * (1 - Math.abs(f) * .25), 1]);
      m.castShadow = false;
    }
  };
  row(-.076, .034, .035, .046, 12, 1);
  row(-.091, .031, .032, .045, 12, .9);
  // eyes: dark sockets with a coal burning in each
  for (const s of [-1, 1]) {
    add(skull, sphere(.018), M.socket, [s * .03, -.011, .064]);
    const e = add(skull, sphere(.0072, 16, 10), M.eye, [s * .03, -.01, .075]);
    e.castShadow = false;
  }
  return skull;
}

function buildHand(wrist, s, M) {
  const hand = { fingers: [], thumb: null, s, wrist };
  add(wrist, new THREE.CylinderGeometry(.046, .044, .045, 20, 1), M.glove, [0, -.005, 0]);
  add(wrist, roundedBox(.034, .1, .086, .014, 5), M.glove, [0, -.058, 0]);
  const zs = [.03, .01, -.01, -.029], ls = [.044, .048, .045, .036];
  zs.forEach((z, i) => {
    const l = ls[i];
    const k1 = joint(wrist, 'finger', [0, -.104, z]);
    add(k1, capsule(.0108, l), M.glove, [0, -l / 2 + .004, 0]);
    const k2 = joint(k1, 'finger2', [0, -l + .004, 0]);
    add(k2, capsule(.0098, l * .82), M.glove, [0, -l * .38, 0]);
    hand.fingers.push([k1, k2]);
  });
  const t1 = joint(wrist, 'thumb', [-s * .008, -.035, .04]);
  t1.rotation.set(-.55, 0, -s * .3);
  add(t1, capsule(.0125, .042), M.glove, [0, -.019, 0]);
  const t2 = joint(t1, 'thumb2', [0, -.04, 0]);
  add(t2, capsule(.0112, .032), M.glove, [0, -.014, 0]);
  hand.thumb = [t1, t2];
  return hand;
}

function curl(hand, c, thumb = c * .5) {
  const s = hand.s;
  for (const [k1, k2] of hand.fingers) { k1.rotation.set(0, 0, -s * c); k2.rotation.set(0, 0, -s * c * 1.15); }
  hand.thumb[0].rotation.set(-.55 - thumb * .3, 0, -s * (.3 + thumb * .5));
  hand.thumb[1].rotation.set(0, 0, -s * thumb * .8);
}

function buildArm(chest, s, M) {
  const shoulder = joint(chest, s > 0 ? 'shoulderL' : 'shoulderR', [s * .195, .15, -.005]);
  add(shoulder, sphere(.065, 28, 18), M.jacket, [s * -.006, -.034, 0], null, [1, 1, .92]);
  add(shoulder, limbGeo(.29, [[0, .068], [.15, .069], [.5, .063], [.85, .055], [1, .052]], { sz: .93 }), M.jacket);
  const elbow = joint(shoulder, 'elbow', [0, -.29, 0]);
  add(elbow, sphere(.053), M.jacket);
  add(elbow, limbGeo(.26, [[0, .053], [.3, .055], [.7, .049], [.9, .045], [1, .047]], { sz: .92 }), M.jacket);
  // zipped cuff
  rod(elbow, [s * .022, -.17, -.044], [s * .027, -.25, -.04], .0026, M.steel, 6);
  add(elbow, new THREE.TorusGeometry(.046, .004, 6, 24), M.jacket, [0, -.252, 0], [Math.PI / 2, 0, 0], [1, .92, 1]);
  const wrist = joint(elbow, 'wrist', [0, -.26, 0]);
  const hand = buildHand(wrist, s, M);
  return { shoulder, elbow, wrist, hand, s, l1: .29, l2: .26 };
}

function buildLeg(hips, s, M) {
  const hip = joint(hips, s > 0 ? 'thighL' : 'thighR', [s * .088, -.06, 0]);
  add(hip, limbGeo(.42, [[0, .09], [.15, .089], [.55, .076], [.88, .063], [1, .061]], { sz: .96 }), M.pants);
  const knee = joint(hip, 'knee', [0, -.42, 0]);
  add(knee, sphere(.062), M.pants, [0, 0, .004]);
  add(knee, limbGeo(.41, [[0, .061], [.22, .062], [.42, .057], [1, .05]], { sz: .96 }), M.pants);
  // biker boot: tall shaft over the calf, buckled straps, chunky sole
  add(knee, limbGeo(.25, [[0, .0605], [.04, .0612], [.5, .0585], [1, .056]], { sz: .97 }), M.boot, [0, -.16, 0]);
  for (const [y, tilt] of [[-.235, .12], [-.305, -.1], [-.36, .08]]) {
    add(knee, new THREE.TorusGeometry(.06, .0045, 6, 28), M.boot, [0, y, 0], [Math.PI / 2 + tilt, 0, 0], [1, .97, 1.6]);
    add(knee, roundedBox(.008, .02, .018, .002, 2), M.chrome, [s * .062, y, 0]);
  }
  const ankle = joint(knee, 'ankle', [0, -.41, 0]);
  add(ankle, sphere(.056), M.boot, [0, -.01, .005]);
  const foot = sculpt(roundedBox(.1, .08, .26, .032, 7), p => {
    const toe = smooth(.02, .13, p.z);
    p.x *= 1 - toe * .18;
    if (p.y > 0) p.y *= 1 - toe * .45;
  });
  add(ankle, foot, M.boot, [0, -.05, .062]);
  add(ankle, roundedBox(.108, .022, .276, .009, 3), M.rubber, [0, -.08, .064]);
  add(ankle, roundedBox(.094, .034, .075, .007, 2), M.rubber, [0, -.076, -.044]);
  add(ankle, new THREE.TorusGeometry(.054, .005, 6, 24), M.boot, [0, -.035, .01], [Math.PI / 2 - .5, 0, 0], [1, 1.25, 1]);
  add(ankle, roundedBox(.008, .018, .02, .002, 2), M.chrome, [s * .056, -.036, .01]);
  return { hip, knee, ankle, s, l1: .42, l2: .41 };
}

function buildRig(root, M) {
  const hips = joint(root, 'hips', [0, .98, 0]);
  // pelvis, belt and buckle
  const pw = spline([[0, .158], [.6, .163], [.85, .156], [1, .13]]);
  add(hips, sculpt(new THREE.CylinderGeometry(1, 1, 1, 48, 12, true), p => {
    const t = .5 - p.y, a = Math.atan2(p.x, p.z), s = Math.sin(a), c = Math.cos(a), k = 2 / SUPER, w = pw(t);
    p.set(Math.sign(s) * Math.pow(Math.abs(s), k) * w, .12 - t * .25, Math.sign(c) * Math.pow(Math.abs(c), k) * w * .74);
  }), M.pants);
  add(hips, sphere(1, 24, 16), M.pants, [0, -.13, 0], null, [.13, .075, .1]);
  add(hips, sculpt(new THREE.CylinderGeometry(1, 1, .034, 56, 1, true), p => {
    const a = Math.atan2(p.x, p.z), s = Math.sin(a), c = Math.cos(a), k = 2 / SUPER;
    p.set(Math.sign(s) * Math.pow(Math.abs(s), k) * .1665, p.y, Math.sign(c) * Math.pow(Math.abs(c), k) * .1235);
  }), M.boot, [0, -.075, 0]);
  add(hips, roundedBox(.062, .044, .012, .005, 3), M.chrome, [0, -.075, .127]);
  add(hips, roundedBox(.036, .022, .006, .003, 2), M.boot, [0, -.075, .132]);

  const spine = joint(hips, 'spine', [0, .02, 0]);
  add(spine, sculpt(new THREE.CylinderGeometry(1, 1, 1, 72, 48, true), p => torsoPoint(p.y + .5, Math.atan2(p.x, p.z), 0, p)), M.jacketTwoSided);
  // collar
  add(spine, new THREE.CylinderGeometry(.094, .077, .07, 40, 2, true, Math.PI * .14, Math.PI * 1.72), M.jacket.clone(), [0, .515, -.01], null, [1, 1, .9]).material.side = THREE.DoubleSide;
  add(spine, new THREE.CylinderGeometry(.074, .074, .02, 24, 1, false), M.lining, [0, .47, 0], null, [1, 1, .85]);
  // lapels, wide and notched, conformed onto the chest
  for (const s of [-1, 1]) {
    const sh = new THREE.Shape();
    const P = [[.028, .497], [.078, .48], [.098, .447], [.081, .435], [.11, .408], [.052, .262], [.03, .285], [.018, .4]].map(([x, y]) => new THREE.Vector2(s * x, y));
    sh.setFromPoints(P);
    const g = new THREE.ExtrudeGeometry(sh, { depth: .005, bevelEnabled: true, bevelThickness: .002, bevelSize: .002, bevelSegments: 1, curveSegments: 2 });
    add(spine, conformFront(g, .004), M.jacket);
  }
  // asymmetric zip and pocket zips
  const zip = [];
  for (let i = 0; i <= 24; i++) {
    const h = .02 + i / 24 * .74, x = .058 - (i / 24) * .09;
    zip.push(torsoPoint(h, torsoAngle(h, x), .004));
  }
  tube(spine, zip, .0026, M.steel, { segs: 60, radial: 6 });
  for (const [x0, h0, x1, h1] of [[.05, .66, .12, .61], [-.15, .3, -.09, .22], [.09, .22, .15, .3]]) {
    const pts = [];
    for (let i = 0; i <= 6; i++) { const f = i / 6, h = h0 + (h1 - h0) * f, x = x0 + (x1 - x0) * f; pts.push(torsoPoint(h, torsoAngle(h, x), .003)); }
    tube(spine, pts, .002, M.steel, { segs: 12, radial: 6 });
  }
  // chain slung over the right shoulder and across the chest to the left hip
  const sling = new THREE.CatmullRomCurve3(Array.from({ length: 48 }, (_, i) => {
    const a = -Math.PI / 2 + i / 48 * TAU, h = .59 + .38 * Math.cos(a + Math.PI / 2);
    return torsoPoint(h, a, .013);
  }), true);
  const slingMesh = chain(sling, M.chain, { k: 1.25, normalAt: (u, p, out) => out.set(p.x, 0, p.z) });
  spine.add(slingMesh);

  const chest = joint(spine, 'chest', [0, .28, 0]);
  const neck = joint(chest, 'neck', [0, .2, 0]);
  add(neck, new THREE.CylinderGeometry(.03, .036, .12, 16, 1), M.socket, [0, .03, -.005]);
  for (let i = 0; i < 3; i++) add(neck, new THREE.CylinderGeometry(.021, .023, .016, 14, 1), M.bone, [0, .02 + i * .022, -.012]);
  const head = joint(neck, 'head', [0, .06, .012]);
  const skull = buildSkull(head, M);

  const armL = buildArm(chest, 1, M), armR = buildArm(chest, -1, M);
  const legL = buildLeg(hips, 1, M), legR = buildLeg(hips, -1, M);

  const hipChains = new THREE.Group();
  hipChains.name = 'hipChains';
  for (const s of [-1, 1]) {
    const c = new THREE.CatmullRomCurve3([[s * .11, -.07, .118], [s * .165, -.24, .085], [s * .19, -.34, .0], [s * .175, -.25, -.085], [s * .12, -.07, -.118]].map(a => new V3(...a)));
    hipChains.add(chain(c, M.chain, { k: 1.1, normalAt: (u, p, out) => out.set(s, 0, 0) }));
  }
  hips.add(hipChains);

  const joints = [];
  root.traverse(o => { if (o.isGroup && o !== root) joints.push(o); });
  const rest = new Map(joints.map(j => [j, j.quaternion.clone()]));
  return { root, hips, spine, chest, neck, head, skull, armL, armR, legL, legR, hipChains, sling, slingMesh, joints, rest };
}

function resetPose(rig) {
  for (const j of rig.joints) j.quaternion.copy(rig.rest.get(j));
}

function poseT(rig) {
  resetPose(rig);
  rig.armL.shoulder.rotation.z = Math.PI / 2 - .04;
  rig.armR.shoulder.rotation.z = -Math.PI / 2 + .04;
  curl(rig.armL.hand, .12, .1);
  curl(rig.armR.hand, .12, .1);
  rig.legL.hip.rotation.z = .045; rig.legL.ankle.rotation.z = -.045;
  rig.legR.hip.rotation.z = -.045; rig.legR.ankle.rotation.z = .045;
  rig.root.updateMatrixWorld(true);
}

function poseStance(rig) {
  resetPose(rig);
  rig.spine.rotation.set(.04, -.06, 0);
  rig.neck.rotation.set(.05, .06, 0);
  rig.head.rotation.set(.12, .08, -.03);
  rig.armL.shoulder.rotation.set(.08, 0, .2);
  rig.armL.elbow.rotation.set(-.32, 0, 0);
  rig.armL.wrist.rotation.set(0, .2, -.1);
  curl(rig.armL.hand, .9, .6);
  rig.armR.shoulder.rotation.set(-.3, .15, -.3);
  rig.armR.elbow.rotation.set(-.75, 0, 0);
  rig.armR.wrist.rotation.set(.1, 0, .25);
  curl(rig.armR.hand, 1.45, 1.2);
  rig.legL.hip.rotation.set(-.04, 0, .09); rig.legL.knee.rotation.x = .05; rig.legL.ankle.rotation.set(-.01, -.15, -.09);
  rig.legR.hip.rotation.set(.06, 0, -.07); rig.legR.knee.rotation.x = .08; rig.legR.ankle.rotation.set(-.14, .2, .07);
  rig.root.updateMatrixWorld(true);
}

/* World directions for an object's local X and Y axes; Z follows. */
function orientXY(obj, x, y) {
  const X = x.clone().normalize(), Y = y.clone().addScaledVector(X, -y.dot(X)).normalize(), Z = new V3().crossVectors(X, Y);
  const q = new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(X, Y, Z));
  obj.quaternion.copy(obj.parent.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(q));
  obj.updateMatrixWorld(true);
}

/* Two-bone IK: bends limb so its end joint lands on target (world), the knee/elbow toward pole. */
function reach(limb, upper, lower, target, pole, isArm) {
  const o = upper.getWorldPosition(new V3());
  const D = target.clone().sub(o);
  const dist = Math.min(D.length(), (limb.l1 + limb.l2) * .999);
  D.normalize();
  const cosA = clamp((limb.l1 * limb.l1 + dist * dist - limb.l2 * limb.l2) / (2 * limb.l1 * dist), -1, 1), sinA = Math.sqrt(1 - cosA * cosA);
  const P = pole.clone().addScaledVector(D, -pole.dot(D)).normalize();
  const d1 = D.clone().multiplyScalar(cosA).addScaledVector(P, sinA);
  const mid = o.clone().addScaledVector(d1, limb.l1);
  const d2 = o.clone().addScaledVector(D, dist).sub(mid).normalize();
  const N = new V3().crossVectors(D, P).normalize();
  if (!isArm) N.negate();
  orientXY(upper, N, d1.clone().negate());
  orientXY(lower, N, d2.clone().negate());
}

/* Seats the rider on the bike. Rider and bike must share a parent sitting at the world origin. */
function poseRide(rig, mounts) {
  resetPose(rig);
  rig.hipChains.visible = false;
  rig.hips.rotation.x = .14;
  rig.spine.rotation.x = .2;
  rig.chest.rotation.x = .05;
  rig.root.updateMatrixWorld(true);
  for (const leg of [rig.legL, rig.legR]) {
    const side = leg.s > 0 ? -1 : 1;   // rider faces +X, so his left is -Z
    const peg = side < 0 ? mounts.pegL : mounts.pegR;
    reach(leg, leg.hip, leg.knee, peg.clone().add(new V3(-.035, .085, 0)), new V3(.5, 1, side * .55), false);
    orientXY(leg.ankle, new V3(0, 0, -1), new V3(-.15, 1, 0));
  }
  for (const arm of [rig.armL, rig.armR]) {
    const side = arm.s > 0 ? -1 : 1;
    const grip = side < 0 ? mounts.gripL : mounts.gripR;
    const F = new V3(1, -.12, -side * .12).normalize();
    reach(arm, arm.shoulder, arm.elbow, grip.clone().addScaledVector(F, -.078).add(new V3(0, .034, 0)), new V3(-.5, -1, side * .45), true);
    orientXY(arm.wrist, new V3(0, arm.s, 0), F.clone().negate());
    curl(arm.hand, 1.55, 1.3);
  }
  orientXY(rig.neck, new V3(0, 0, -1), new V3(.42, 1, 0));
  orientXY(rig.head, new V3(0, 0, -1), new V3(.1, 1, 0));
}

/* --- emitters (rand, outPos, outDir) */
const emitSkull = (r, p, n) => {
  for (;;) {
    randDir(r, n);
    if (n.y < -.2) continue;
    if (n.z > .3 && n.y < .5) continue;      // keep the face clear
    break;
  }
  p.set(n.x * .068, n.y * .07, n.z * .087).multiplyScalar(.93);
  n.y += .7;
  n.normalize();
};
const emitCrown = (r, p, n) => {
  randDir(r, n);
  n.y = Math.abs(n.y) + 2.2;
  n.normalize();
  p.set(n.x * .06, .064, n.z * .07 - .005);
};

function riderFire(rig, blaze) {
  const s = rig.skull;
  s.add(new Fire({ count: Math.round(560 * blaze), emit: emitSkull, size: [.07 * Math.sqrt(blaze), .03], life: .75, rise: .3 * blaze, spread: .05, turb: .035, stretch: 1.8, intensity: .55, seed: 3 }));
  s.add(new Fire({ count: Math.round(220 * blaze), emit: emitSkull, size: [.032, .012], life: .45, rise: .12 * blaze, spread: .02, turb: .015, stretch: 1.5, intensity: .9, seed: 13 }));
  s.add(new Fire({ count: Math.round(240 * blaze), emit: emitSkull, size: [.026, .01], life: .6, rise: .38 * blaze, spread: .07, turb: .06, stretch: 3.2, intensity: 1, seed: 14 }));
  s.add(new Fire({ count: 120, emit: emitCrown, size: [.034, .012], life: .42, rise: .14 * blaze, spread: .015, turb: .01, palette: 'blue', intensity: .9, seed: 4 }));
  s.add(new Fire({
    count: 70, size: [.011, .004], life: .35, rise: .05, spread: .03, turb: .008, stretch: 2, intensity: .9, seed: 5,
    emit: (r, p, n) => { const side = r() < .5 ? -1 : 1; p.set(side * .03 + (r() - .5) * .01, -.006, .078); n.set(side * .3, .6, 1).normalize(); },
  }));
  const l = new FireLight(0xff7a2a, .3 * blaze, 2, 1);
  l.position.set(0, .26, -.06);
  s.add(l);
  const face = new FireLight(0xff9a40, .08, .45, 2);
  face.position.set(0, -.02, .16);
  s.add(face);
}

/* The rider on foot. */
export function createRider(opts = {}) {
  const { pose = 'stance', fire = true, blaze = 1 } = opts;
  const M = materials();
  const root = new THREE.Group();
  root.name = 'GhostRider';
  const rig = buildRig(root, M);
  root.userData.rig = rig;
  if (fire) riderFire(rig, blaze);
  if (pose === 'tpose') poseT(rig);
  else if (pose === 'stance') {
    poseStance(rig);
    whip(root, rig, M, fire);
  }
  const animate = fireAnimator(root);
  root.userData.update = (t) => animate(t);
  return root;
}

/* A burning chain whip hanging from the right fist and pooling on the floor, spike at the end. */
function whip(root, rig, M, fire) {
  root.updateMatrixWorld(true);
  const w = rig.armR.wrist, inv = root.matrixWorld.clone().invert();
  const grip = new V3(0, -.085, .0).applyMatrix4(w.matrixWorld).applyMatrix4(inv);
  const out = new V3(0, -.07, .02).applyMatrix4(w.matrixWorld).applyMatrix4(inv);
  const g = grip, d = out.clone().sub(grip).normalize();
  const pts = [g.clone().addScaledVector(d, -.03), g.clone(), g.clone().addScaledVector(d, .1)];
  const base = new V3(g.x - .02, .016, g.z + .2);
  pts.push(new V3(g.x - .05, g.y * .5, g.z + .12), new V3(g.x - .045, .12, g.z + .18), base);
  for (let i = 1; i <= 14; i++) {
    const a = i / 14 * TAU * 1.15 + 2.2, r = .11 - i * .003;
    pts.push(new V3(base.x + .1 + Math.cos(a) * r, .016, base.z + .1 + Math.sin(a) * r));
  }
  pts.push(new V3(base.x + .3, .016, base.z + .26), new V3(base.x + .48, .016, base.z + .3));
  const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
  const links = chain(curve, M.chain, { k: 1.25, normalAt: (u, p, o) => o.set(0, 1, 0) });
  root.add(links);
  const tip = curve.getPointAt(1), dir = curve.getTangentAt(1);
  const spike = add(root, new THREE.ConeGeometry(.022, .1, 6), M.steel, [tip.x, tip.y, tip.z]);
  spike.quaternion.setFromUnitVectors(_yAxis, dir);
  spike.position.addScaledVector(dir, .055);
  const collar = add(root, new THREE.CylinderGeometry(.016, .02, .025, 10), M.darkMetal, [tip.x, tip.y, tip.z]);
  collar.quaternion.copy(spike.quaternion);
  if (fire) {
    root.add(new Fire({
      count: 460, size: [.03, .012], life: .55, rise: .17, spread: .015, turb: .02, stretch: 1.7, intensity: 1.1, seed: 21,
      emit: (r, p, n) => { curve.getPointAt(Math.pow(r(), .8), p); randDir(r, n); n.y = Math.abs(n.y); },
    }));
    const l = new FireLight(0xff6a1a, .6, 1.4, 4);
    l.position.copy(base).add(new V3(.1, .1, .1));
    root.add(l);
  }
}

/* ---------------------------------------------------------------- the bike */

const AXLE = .34, REAR_X = -.8, FRONT_X = .88;
const RAKE = 34 * Math.PI / 180;
const FORK = new V3(-Math.sin(RAKE), Math.cos(RAKE), 0);

function emitTire(R, rt, wz) {
  return (r, p, n) => {
    const u = r() * TAU, v = (r() - .5) * Math.PI * 1.3, c = Math.cos(v);
    p.set((R + rt * c) * Math.cos(u), (R + rt * c) * Math.sin(u), rt * Math.sin(v) * wz);
    n.set(c * Math.cos(u), c * Math.sin(u), Math.sin(v)).normalize();
  };
}

function buildWheel({ R, rt, wz, rimR, M, disc, fire, blaze, seed }) {
  const mount = new THREE.Group();
  const spin = new THREE.Group();
  mount.add(spin);
  add(spin, new THREE.TorusGeometry(R, rt, 24, 80), M.tire, null, null, [1, 1, wz]);
  // cast rim: seven spokes left between triangular windows
  const sh = new THREE.Shape();
  sh.absarc(0, 0, rimR, 0, TAU, false);
  for (let i = 0; i < 7; i++) {
    const a = i / 7 * TAU, r0 = rimR * .36, r1 = rimR * .86, da = .3, hole = new THREE.Path();
    hole.moveTo(Math.cos(a) * r0, Math.sin(a) * r0);
    hole.lineTo(Math.cos(a - da) * r1, Math.sin(a - da) * r1);
    hole.absarc(0, 0, r1, a - da, a + da, false);
    hole.lineTo(Math.cos(a) * r0, Math.sin(a) * r0);
    sh.holes.push(hole);
  }
  const rimGeo = new THREE.ExtrudeGeometry(sh, { depth: .03, bevelEnabled: true, bevelThickness: .006, bevelSize: .006, bevelSegments: 1, curveSegments: 10 });
  rimGeo.translate(0, 0, -.015);
  add(spin, rimGeo, M.blackMetal);
  add(spin, new THREE.CylinderGeometry(rimR, rimR, rt * wz * 1.5, 48, 1, true), M.darkMetal, null, [Math.PI / 2, 0, 0]);
  for (const z of [-1, 1]) add(spin, new THREE.TorusGeometry(rimR, .008, 8, 64), M.chrome, [0, 0, z * rt * wz * .75]);
  add(spin, new THREE.CylinderGeometry(.045, .045, .15, 24), M.chrome, null, [Math.PI / 2, 0, 0]);
  for (let i = 0; i < 7; i++) {
    const a = (i + .5) / 7 * TAU;
    add(spin, new THREE.CylinderGeometry(.006, .006, .04, 6), M.chrome, [Math.cos(a) * .06, Math.sin(a) * .06, 0], [Math.PI / 2, 0, 0]);
  }
  if (disc) {
    add(spin, new THREE.CylinderGeometry(.14, .14, .006, 48), M.steel, [0, 0, .07], [Math.PI / 2, 0, 0]);
    add(spin, new THREE.CylinderGeometry(.085, .085, .008, 32), M.blackMetal, [0, 0, .07], [Math.PI / 2, 0, 0]);
    add(mount, roundedBox(.07, .05, .04, .01), M.darkMetal, [-.08, .11, .08], [0, 0, .7]);
  } else {
    add(spin, new THREE.CylinderGeometry(.14, .14, .02, 48), M.darkMetal, [0, 0, -.085], [Math.PI / 2, 0, 0]);
    add(spin, new THREE.CylinderGeometry(.11, .11, .024, 48), M.chrome, [0, 0, -.085], [Math.PI / 2, 0, 0]);
  }
  if (fire) {
    mount.add(new Fire({ count: Math.round(700 * blaze), emit: emitTire(R, rt, wz), size: [.055, .022], life: .55, rise: .22 * blaze, spread: .07, turb: .03, stretch: 1.9, intensity: 1.5, seed }));
    mount.add(new Fire({ count: Math.round(300 * blaze), emit: emitTire(R, rt * .9, wz), size: [.028, .011], life: .35, rise: .08, spread: .03, turb: .012, stretch: 1.4, intensity: 1.8, seed: seed + 1 }));
    mount.add(new Fire({ count: Math.round(160 * blaze), emit: emitTire(R, rt, wz), size: [.024, .01], life: .6, rise: .36 * blaze, spread: .1, turb: .06, stretch: 3, intensity: 1.6, seed: seed + 2 }));
    const l = new FireLight(0xff6a1a, 1.1 * blaze, 1.6, seed);
    l.position.set(0, R * .3, 0);
    mount.add(l);
  }
  return { mount, spin, R: R + rt };
}

export function createHellCycle(opts = {}) {
  const { fire = true, parked = true, blaze = 1 } = opts;
  const M = materials();
  const bike = new THREE.Group();
  bike.name = 'HellCycle';
  const frame = new THREE.Group();
  frame.name = 'frame';
  bike.add(frame);

  const rear = buildWheel({ R: .255, rt: .085, wz: 1.35, rimR: .2, M, disc: false, fire, blaze, seed: 31 });
  rear.mount.position.set(REAR_X, AXLE, 0);
  const front = buildWheel({ R: .27, rt: .07, wz: 1.1, rimR: .215, M, disc: true, fire, blaze, seed: 41 });
  front.mount.position.set(FRONT_X, AXLE, 0);
  bike.add(rear.mount, front.mount);

  // frame: backbone, twin cradle rails, seat stays, chain stays
  const T = .022;
  tube(frame, [[.5, .95, 0], [.3, .865, 0], [0, .8, 0], [-.22, .72, 0], [-.33, .6, 0]], T, M.blackMetal);
  for (const z of [-1, 1]) {
    tube(frame, [[.52, .87, z * .02], [.45, .62, z * .05], [.35, .3, z * .065], [.24, .17, z * .072], [-.1, .15, z * .075], [-.3, .2, z * .075], [-.36, .4, z * .065], [-.32, .62, z * .045]], T * .9, M.blackMetal);
    tube(frame, [[-.31, .64, z * .045], [-.52, .5, z * .085], [-.78, .36, z * .1]], T * .8, M.blackMetal);
    tube(frame, [[-.3, .2, z * .075], [-.55, .28, z * .092], [-.78, .335, z * .1]], T * .8, M.blackMetal);
    add(frame, roundedBox(.08, .06, .012, .01), M.darkMetal, [REAR_X, AXLE, z * .105]);
  }
  rod(frame, [.545, .837, 0], [.489, .92, 0], .032, M.blackMetal, 16);

  // fork, triple trees, headlight
  const ax = new V3(FRONT_X, AXLE, 0), at = f => ax.clone().addScaledVector(FORK, f).toArray();
  for (const z of [-1, 1]) {
    const o = [0, 0, z * .085];
    const a = at(.0), b = at(.33), c = at(.72);
    rod(frame, [a[0], a[1], o[2]], [b[0], b[1], o[2]], .03, M.chrome, 16, .028);
    rod(frame, [b[0], b[1], o[2]], [c[0], c[1], o[2]], .022, M.blackMetal, 16);
  }
  for (const f of [.6, .7]) {
    const p = at(f);
    const m = add(frame, roundedBox(.07, .026, .23, .01), M.darkMetal, p);
    m.quaternion.setFromUnitVectors(_yAxis, FORK);
  }
  const hl = new V3(...at(.5)).add(new V3(.105, 0, 0));
  add(frame, new THREE.CylinderGeometry(.085, .07, .1, 32), M.blackMetal, hl.toArray(), [0, 0, -Math.PI / 2]);
  add(frame, sphere(.07, 24, 12), M.blackMetal, [hl.x - .05, hl.y, 0], null, [.8, 1, 1]);
  add(frame, new THREE.TorusGeometry(.082, .009, 10, 40), M.chrome, [hl.x + .05, hl.y, 0], [0, Math.PI / 2, 0]);
  add(frame, new THREE.CircleGeometry(.077, 40), M.lens, [hl.x + .052, hl.y, 0], [0, Math.PI / 2, 0]).castShadow = false;
  for (const z of [-1, 1]) rod(frame, [hl.x - .02, hl.y, z * .06], [hl.x - .09, hl.y + .02, z * .085], .008, M.chrome, 6);

  // handlebars, grips, levers, mirrors
  const grips = {};
  for (const z of [-1, 1]) {
    tube(frame, [[.49, .965, z * .03], [.475, 1.04, z * .07], [.43, 1.085, z * .18], [.375, 1.1, z * .3], [.36, 1.1, z * .44]], .013, M.blackMetal, { segs: 32, radial: 10 });
    add(frame, new THREE.CylinderGeometry(.018, .018, .12, 16), M.rubber, [.36, 1.1, z * .375], [Math.PI / 2, 0, 0]);
    add(frame, new THREE.CylinderGeometry(.02, .02, .012, 16), M.chrome, [.36, 1.1, z * .44], [Math.PI / 2, 0, 0]);
    tube(frame, [[.37, 1.1, z * .3], [.42, 1.1, z * .34], [.44, 1.095, z * .42]], .005, M.chrome, { segs: 10, radial: 6 });
    rod(frame, [.37, 1.1, z * .425], [.35, 1.22, z * .5], .0045, M.chrome, 6);
    add(frame, new THREE.CylinderGeometry(.036, .036, .01, 20), M.chrome, [.35, 1.235, z * .505], [0, 0, Math.PI / 2 - .2]);
    grips[z < 0 ? 'gripL' : 'gripR'] = new V3(.36, 1.1, z * .375);
  }

  // tank with blue flames, gas cap; seat
  const tank = add(frame, sculpt(new THREE.SphereGeometry(1, 64, 40), p => {
    const rearT = smooth(0, 1, -p.x);
    const x = p.x * .27, y = p.y * .105 * (p.y < 0 ? .62 : 1) * (1 - .18 * rearT), z = p.z * .135 * (1 - .32 * rearT);
    p.set(x, y, z);
  }), M.paint, [.24, .915, 0], [0, 0, .12]);
  tank.castShadow = true;
  add(frame, new THREE.CylinderGeometry(.022, .024, .014, 20), M.chrome, [.27, 1.022, 0]);
  add(frame, sculpt(new THREE.SphereGeometry(1, 48, 24), p => {
    const nose = smooth(-.2, 1, p.x), lip = smooth(-.3, -1, p.x);
    const x = p.x * .18, y = p.y * (p.y > 0 ? .036 + lip * .03 : .022), z = p.z * .13 * (1 - nose * .5);
    p.set(x, y, z);
  }), M.seat, [-.17, .78, 0]);
  add(frame, roundedBox(.16, .02, .12, .008), M.darkMetal, [-.18, .752, 0]);

  // fenders
  const fender = (cx, R, w, a0, a1) => {
    const g = new THREE.CylinderGeometry(R, R, w, 64, 4, true, (a0 + 90) * Math.PI / 180, (a1 - a0) * Math.PI / 180);
    sculpt(g, p => {
      const e = (p.y / (w / 2)) ** 2, rr = Math.hypot(p.x, p.z), k = (rr - .025 * e) / rr;
      p.x *= k; p.z *= k;
    });
    g.rotateX(Math.PI / 2);
    const m = add(frame, g, M.blackMetal, [cx, AXLE, 0]);
    m.material = M.blackMetal.clone();
    m.material.side = THREE.DoubleSide;
    return m;
  };
  fender(REAR_X, .385, .27, 22, 192);
  fender(FRONT_X, .36, .17, 35, 128);
  const tl = new V3(REAR_X + .392 * Math.cos(2.62), AXLE + .392 * Math.sin(2.62), 0);
  add(frame, roundedBox(.03, .04, .07, .008), M.tail, tl.toArray(), [0, 0, 2.62]).castShadow = false;
  for (const z of [-1, 1]) rod(frame, [REAR_X, AXLE, z * .11], [REAR_X - .15, AXLE + .34, z * .13], .011, M.blackMetal, 8);

  // V-twin
  add(frame, roundedBox(.3, .18, .17, .045), M.darkMetal, [.02, .33, 0]);
  const heads = [];
  for (const s of [1, -1]) {
    const cyl = joint(frame, 'cylinder', [.02 + s * .03, .4, 0]);
    cyl.rotation.z = -s * .42;
    add(cyl, new THREE.CylinderGeometry(.05, .05, .2, 24), M.darkMetal, [0, .1, 0]);
    for (let i = 0; i < 9; i++) add(cyl, new THREE.CylinderGeometry(.074 - i * .0006, .074 - i * .0006, .007, 32), M.darkMetal, [0, .025 + i * .019, 0]).castShadow = i % 2 === 0;
    for (let i = 0; i < 3; i++) add(cyl, new THREE.CylinderGeometry(.08, .08, .008, 32), M.steel, [0, .2 + i * .016, 0]);
    add(cyl, roundedBox(.135, .05, .108, .02), M.chrome, [0, .27, 0]);
    add(cyl, new THREE.CylinderGeometry(.006, .006, .03, 8), M.chrome, [s * .05, .22, .06], [.6, 0, 0]);
    rod(frame, [.02 + s * .05, .36, .06], [.02 + s * .05 + s * .1, .62, .055], .008, M.chrome, 8);
    heads.push(cyl);
  }
  add(frame, new THREE.CylinderGeometry(.085, .085, .045, 36), M.blackMetal, [.02, .56, .1], [Math.PI / 2, 0, 0]);
  add(frame, new THREE.TorusGeometry(.085, .009, 10, 40), M.chrome, [.02, .56, .123]);
  add(frame, roundedBox(.4, .15, .05, .03), M.blackMetal, [-.13, .3, -.11]);
  add(frame, new THREE.CylinderGeometry(.06, .06, .02, 32), M.chrome, [.02, .3, -.14], [Math.PI / 2, 0, 0]);
  add(frame, roundedBox(.2, .15, .15, .03), M.darkMetal, [-.22, .34, 0]);
  add(frame, new THREE.CylinderGeometry(.052, .052, .17, 28), M.blackMetal, [-.3, .6, 0], [Math.PI / 2, 0, 0]);
  for (const z of [-1, 1]) add(frame, new THREE.TorusGeometry(.05, .006, 8, 28), M.chrome, [-.3, .6, z * .085]);
  add(frame, roundedBox(.12, .1, .14, .012), M.blackMetal, [-.36, .46, 0]);
  // belt drive (left side)
  add(frame, new THREE.CylinderGeometry(.05, .05, .025, 24), M.chrome, [-.24, .3, -.1], [Math.PI / 2, 0, 0]);
  for (const dy of [-1, 1]) rod(frame, [-.24, .3 + dy * .05, -.1], [REAR_X, AXLE + dy * .14, -.085], .006, M.rubber, 6);

  // exhaust: two black pipes down the right side, chrome slash-cut tips venting blue fire
  const pipes = [
    [[.17, .6, .06], [.25, .46, .12], [.16, .24, .165], [-.2, .22, .18], [-.6, .3, .19], [-.95, .37, .19]],
    [[-.16, .6, .07], [-.23, .48, .15], [-.36, .41, .19], [-.62, .43, .2], [-.93, .47, .2]],
  ];
  const tips = [];
  for (const pts of pipes) {
    const p = tube(frame, pts, .024, M.blackMetal, { segs: 80, radial: 14 });
    const c = p.userData.curve, end = c.getPointAt(1), dir = c.getTangentAt(1);
    const tipM = add(frame, new THREE.CylinderGeometry(.03, .03, .1, 20, 1, true), M.chrome);
    tipM.material = M.chrome.clone();
    tipM.material.side = THREE.DoubleSide;
    tipM.quaternion.setFromUnitVectors(_yAxis, dir);
    tipM.position.copy(end).addScaledVector(dir, .02);
    const glow = add(frame, new THREE.CircleGeometry(.026, 20), M.blueGlow);
    glow.quaternion.setFromUnitVectors(new V3(0, 0, 1), dir);
    glow.position.copy(end).addScaledVector(dir, .03);
    glow.castShadow = false;
    tips.push({ end: end.clone().addScaledVector(dir, .07), dir });
  }

  // forward controls and pegs
  const pegs = {};
  for (const z of [-1, 1]) {
    rod(frame, [.3, .26, z * .07], [.48, .36, z * .2], .012, M.blackMetal, 8);
    add(frame, new THREE.CylinderGeometry(.017, .017, .1, 12), M.rubber, [.48, .36, z * .25], [Math.PI / 2, 0, 0]);
    pegs[z < 0 ? 'pegL' : 'pegR'] = new V3(.48, .36, z * .25);
  }

  // saddlebag on the left
  const bag = joint(frame, 'saddlebag', [-.63, .53, -.215]);
  add(bag, roundedBox(.27, .2, .085, .03), M.seat);
  add(bag, roundedBox(.278, .075, .092, .02), M.seat, [0, .07, 0]);
  for (const x of [-.07, .07]) {
    add(bag, roundedBox(.024, .16, .006, .003), M.pants, [x, .01, -.046]);
    add(bag, roundedBox(.02, .016, .008, .003), M.chrome, [x, -.03, -.049]);
  }

  if (!parked) { /* kickstand up */ } else rod(frame, [-.04, .2, -.08], [.12, .012, -.3], .011, M.blackMetal, 8);

  if (fire) {
    for (const [i, t] of tips.entries()) {
      const fx = new Fire({
        count: Math.round(300 * blaze), size: [.036, .016], life: .32, rise: .04, spread: .34 * blaze, turb: .01, stretch: 2.6, palette: 'blue', intensity: 1.8, seed: 51 + i, windScale: .7,
        emit: (r, p, n) => { p.copy(t.end).add(new V3((r() - .5) * .02, (r() - .5) * .02, (r() - .5) * .02)); n.copy(t.dir).add(new V3((r() - .5) * .25, (r() - .5) * .25 + .1, (r() - .5) * .25)).normalize(); },
      });
      frame.add(fx);
    }
    const bl = new FireLight(0x3a7bff, .6, 1.2, 9);
    bl.position.copy(tips[0].end).add(new V3(-.08, .02, 0));
    frame.add(bl);
  }

  const mounts = { ...grips, ...pegs };
  bike.userData.mounts = mounts;
  bike.userData.wheels = [rear, front];
  bike.userData.heads = heads;
  bike.userData.tips = tips;
  const animate = fireAnimator(bike);
  bike.userData.update = (t, o = {}) => animate(t, o.wind);
  return bike;
}

/* ---------------------------------------------------------------- riding */

export function createRidingGhostRider(opts = {}) {
  const { fire = true } = opts;
  const M = materials();
  const group = new THREE.Group();
  group.name = 'GhostRiderRiding';
  const bike = createHellCycle({ fire, parked: false, blaze: 1.45 });
  group.add(bike);
  const rider = createRider({ pose: 'none', fire, blaze: 1.75 });
  rider.rotation.y = Math.PI / 2;
  rider.position.set(-.17, -.05, 0);
  group.add(rider);
  group.updateMatrixWorld(true);
  const rig = rider.userData.rig;
  poseRide(rig, bike.userData.mounts);

  let streak = null;
  if (fire) {
    // flames pouring off his back and shoulders, the slung chain alight, fire leaking from the cuffs
    rig.spine.add(new Fire({
      count: 600, size: [.05, .02], life: .6, rise: .22, spread: .05, turb: .03, stretch: 1.9, intensity: 1.1, seed: 61, windScale: 1.2,
      emit: (r, p, n) => { const h = .55 + r() * .45, a = Math.PI + (r() - .5) * 3.6; torsoPoint(h, a, .01, p); n.set(p.x, 0, p.z).normalize(); n.y = .6; n.normalize(); },
    }));
    rig.spine.add(new Fire({
      count: 400, size: [.028, .011], life: .45, rise: .15, spread: .02, turb: .02, stretch: 1.7, intensity: 1.4, seed: 62, windScale: 1.1,
      emit: (r, p, n) => { rig.sling.getPointAt(r(), p); n.set(p.x, 0, p.z).normalize(); n.y = .8; n.normalize(); },
    }));
    for (const [i, arm] of [rig.armL, rig.armR].entries()) {
      arm.elbow.add(new Fire({
        count: 140, size: [.03, .012], life: .4, rise: .12, spread: .03, turb: .015, stretch: 1.8, intensity: 1.4, seed: 70 + i, windScale: 1,
        emit: (r, p, n) => { const a = r() * TAU; p.set(Math.cos(a) * .043, -.25 + r() * .02, Math.sin(a) * .04); n.set(Math.cos(a), -.3, Math.sin(a)).normalize(); },
      }));
    }
    // a hellfire engine and a road that burns behind him
    for (const [i, cyl] of bike.userData.heads.entries()) {
      cyl.add(new Fire({
        count: 240, size: [.04, .016], life: .5, rise: .2, spread: .05, turb: .025, stretch: 1.8, intensity: 1.2, seed: 80 + i, windScale: 1,
        emit: (r, p, n) => { const a = r() * TAU, y = .03 + r() * .26; p.set(Math.cos(a) * .078, y, Math.sin(a) * .078); n.set(Math.cos(a), .4, Math.sin(a)).normalize(); },
      }));
    }
    const trail = new Fire({
      count: 1100, size: [.06, .03], life: .9, rise: .24, spread: .05, turb: .05, stretch: 2.2, intensity: .9, seed: 90, windScale: 3.2,
      emit: (r, p, n) => { const front = r() < .35; p.set((front ? FRONT_X : REAR_X) - .05 - r() * .1, .015 + r() * .04, (r() - .5) * .16); n.set(-.4, 1, (r() - .5) * .6).normalize(); },
    });
    group.add(trail);
    group.add(new Fire({
      count: 260, size: [.008, .003], life: 1.6, rise: .9, spread: .3, turb: .25, stretch: 3, palette: 'ember', intensity: 1, seed: 95, windScale: 2.6,
      emit: (r, p, n) => { p.set(-1 + r() * 2, .05 + r() * 1.5, (r() - .5) * .6); randDir(r, n); },
    }));
    streak = add(group, new THREE.PlaneGeometry(3.2, .17), M.streak, [REAR_X - 1.5, .004, 0], [-Math.PI / 2, 0, Math.PI]);
    streak.castShadow = streak.receiveShadow = false;
    streak.renderOrder = 5;
  }

  const animate = fireAnimator(group);
  const wind = new V3();
  let speed = 0, last = null;
  group.userData.rig = rig;
  group.userData.bike = bike;
  group.userData.speed = () => speed;
  group.userData.update = (t, o = {}) => {
    const dt = last === null ? 0 : Math.min(.1, t - last);
    last = t;
    const goal = o.throttle === undefined ? 1 : o.throttle;
    speed += (goal - speed) * Math.min(1, dt * 2.2);
    for (const w of bike.userData.wheels) w.spin.rotation.z -= dt * speed * 9 / w.R;
    wind.set(-1.5 * speed, .08 * speed, 0);
    bike.position.y = speed * .0025 * Math.sin(t * 57);
    rider.position.y = -.05 + speed * .004 * Math.sin(t * 31);
    animate(t, wind);
    if (streak) streak.material.opacity = .6 * speed;
  };
  return group;
}
