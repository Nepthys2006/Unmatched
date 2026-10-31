// Exports the procedural Ghost Rider models (assets/web3d/ghost-rider/model.js) as .glb files, without
// the particle fire (that only exists in the shader). Builds them in headless Chromium, because the
// models use canvas textures. Run: node tool/export_ghost_rider.mjs
//   -> assets/web3d/ghost-rider/models/{ghost-rider-tpose,ghost-rider,hell-cycle,ghost-rider-riding}.glb
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const assets = path.join(here, '..', 'assets');
const outDir = path.join(assets, 'web3d', 'ghost-rider', 'models');
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.ttf': 'font/ttf' };

const server = http.createServer((req, res) => {
  const file = path.join(assets, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!file.startsWith(assets) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
try {
  const page = await browser.newPage();
  page.on('pageerror', e => console.error('page error:', e.message));
  await page.goto(`${base}/web3d/ghost-rider/index.html#rider`);
  await page.waitForFunction(() => window.__ghostRider, null, { timeout: 120000 });
  const files = await page.evaluate(async () => {
    __ghostRider.renderer.setAnimationLoop(null);
    const { GLTFExporter } = await import('three/addons/exporters/GLTFExporter.js');
    const M = await import('./model.js');
    const models = {
      'ghost-rider-tpose': M.createRider({ pose: 'tpose', fire: false }),
      'ghost-rider': M.createRider({ pose: 'stance', fire: false }),
      'hell-cycle': M.createHellCycle({ fire: false }),
      'ghost-rider-riding': M.createRidingGhostRider({ fire: false }),
    };
    // The builders make a fresh geometry per part; share identical ones so each is stored once.
    const hashGeo = g => {
      let h = 2166136261;
      for (const a of [g.attributes.position, g.attributes.normal, g.index].filter(Boolean)) {
        const v = new Uint32Array(a.array.buffer, a.array.byteOffset, a.array.byteLength >> 2);
        for (let i = 0; i < v.length; i++) h = Math.imul(h ^ v[i], 16777619);
        h = Math.imul(h ^ v.length, 16777619);
      }
      return h >>> 0;
    };
    const out = {};
    const exporter = new GLTFExporter();
    for (const [name, obj] of Object.entries(models)) {
      obj.traverse(o => { if (o.isMesh && !o.visible) o.parent.remove(o); });
      const seen = new Map();
      obj.traverse(o => {
        if (!o.isMesh || o.isInstancedMesh) return;
        const k = hashGeo(o.geometry);
        if (seen.has(k)) o.geometry = seen.get(k); else seen.set(k, o.geometry);
      });
      const buf = await exporter.parseAsync(obj, { binary: true, maxTextureSize: 1024 });
      let s = '';
      const bytes = new Uint8Array(buf);
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      out[name] = btoa(s);
    }
    return out;
  });
  fs.mkdirSync(outDir, { recursive: true });
  for (const [name, b64] of Object.entries(files)) {
    const file = path.join(outDir, `${name}.glb`);
    fs.writeFileSync(file, Buffer.from(b64, 'base64'));
    console.log(`${path.relative(path.join(here, '..'), file)}  ${(fs.statSync(file).size / 1024).toFixed(0)} KB`);
  }
} finally {
  await browser.close();
  server.close();
}
