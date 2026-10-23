// Exports the battlefields of the Three.js table (../3D Map/src/03-maps.js) as plain graph JSON
// so the Flutter game plays on exactly the same boards. Run: node tool/export_maps.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const src = path.join(here, '..', '..', '3D Map', 'src');
const core = fs.readFileSync(path.join(src, '01-core.js'), 'utf8');
const helpers = core.split('\n').filter(l => /^function mulberry|^const hash2/.test(l)).join('\n');
const maps = fs.readFileSync(path.join(src, '03-maps.js'), 'utf8').replace('__HERO_DATA__', '{}');
const { MAPS, buildGraph } = new Function(helpers + '\n' + maps + '\nreturn { MAPS, buildGraph };')();

const out = {};
for (const [id, m] of Object.entries(MAPS)) {
  const { nodes, edgeList } = buildGraph(m);
  out[id] = {
    id, name: m.name, mode: m.mode, theme: m.theme, blurb: m.blurb, river: !!m.river, sea: !!m.sea,
    zones: Object.fromEntries(Object.entries(m.zones).map(([k, [name, color]]) => [k, { name, color }])),
    spaces: nodes.map(n => ({ id: n.id, x: +n.x.toFixed(4), y: +n.z.toFixed(4), zones: n.zones, start: n.start || null })),
    links: edgeList.map(e => [e.a, e.b]),
  };
}
out.star = starMap();
fs.writeFileSync(path.join(here, '..', 'assets', 'data', 'maps.json'), JSON.stringify(out));

/** A five-armed free-for-all board (none of the 3D table's boards has five start spaces).
 *  A central circle zone, five sectors with a start at each tip, and border spaces shared by
 *  neighbouring sectors. Rotationally symmetric, so every start is equally far from the rest. */
function starMap() {
  const zoneKeys = ['a', 'b', 'c', 'd', 'e'];
  const zones = {
    h: { name: 'Moonstone Circle', color: '#b8a2ea' },
    a: { name: 'Ember Arm', color: '#e6776c' }, b: { name: 'Gold Arm', color: '#efc76c' },
    c: { name: 'Fern Arm', color: '#86c590' }, d: { name: 'Tide Arm', color: '#80b9e8' },
    e: { name: 'Dusk Arm', color: '#cfa77a' },
  };
  const spaces = [], links = [];
  const add = (r, deg, zs, start = null) => {
    const a = (deg - 90) * Math.PI / 180;
    spaces.push({ id: spaces.length, x: +(r * Math.cos(a) * 1.25).toFixed(4), y: +(r * Math.sin(a)).toFixed(4), zones: zs, start });
    return spaces.length - 1;
  };
  const link = (a, b) => links.push([a, b]);
  const hub = add(0, 0, ['h']);
  const I = [], M = [], O = [], L = [], R = [], B = [];
  for (let k = 0; k < 5; k++) {
    const t = k * 72;
    I.push(add(1.1, t, ['h', zoneKeys[k]]));
    M.push(add(2.1, t, [zoneKeys[k]]));
    L.push(add(2.75, t - 17, [zoneKeys[k]]));
    R.push(add(2.75, t + 17, [zoneKeys[k]]));
    O.push(add(3.3, t, [zoneKeys[k]], k + 1));
    B.push(add(2.35, t + 36, [zoneKeys[k], zoneKeys[(k + 1) % 5]]));
  }
  for (let k = 0; k < 5; k++) {
    const n = (k + 1) % 5, p = (k + 4) % 5;
    link(hub, I[k]); link(I[k], I[n]); link(I[k], M[k]);
    link(M[k], L[k]); link(M[k], R[k]); link(L[k], O[k]); link(R[k], O[k]);
    link(R[k], B[k]); link(B[k], L[n]); link(B[k], I[k]); link(B[k], I[n]);
    void p;
  }
  return { id: 'star', name: 'Pentacle Ruins', mode: 'ffa', theme: 'ruins', blurb: 'Five arms around a moonstone circle. Built for up to five heroes; every tip is a start.', river: false, sea: false, zones, spaces, links };
}
for (const m of Object.values(out)) console.log(m.id.padEnd(8), m.mode.padEnd(4), m.spaces.length, 'spaces', m.links.length, 'links', 'starts', m.spaces.filter(s => s.start).map(s => s.start).join(','));
