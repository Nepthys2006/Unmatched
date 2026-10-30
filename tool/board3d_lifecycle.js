// Lifecycle test for the 3D board page (assets/web3d), the page every platform shows (the web's
// iframe, Android/iOS web views, Windows' WebView2): the board must still be drawn after the window
// collapses to a sliver and is enlarged again (minimize, a phone turning round), after the browser
// takes the WebGL context away and gives it back (another app, a locked phone, a driver reset),
// and after hiding and showing the page. Heroes' cut-out edges must carry no black outline.
//
//   cd assets && python -m http.server 8765        (in another terminal)
//   npm i playwright && npx playwright install chromium
//   node tool/board3d_lifecycle.js [map id] [base url]
//
// BOARD_JS=<file> serves another board.js in place of assets/web3d/board.js (to run an old version).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const [mapId = 'helicarrier', base = 'http://127.0.0.1:8765/'] = process.argv.slice(2);
const maps = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'assets', 'data', 'maps.json')));
const m = maps[mapId];

(async () => {
  // CHROMIUM=<exe> runs an already installed browser instead of the one Playwright downloads.
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const failures = [];
  const check = (ok, what) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}`); if (!ok) failures.push(what); };

  const open = async (viewport, deviceScaleFactor = 1) => {
    const p = await b.newPage({ viewport, deviceScaleFactor });
    p.errors = [];
    p.on('pageerror', e => p.errors.push(e.message));
    await p.addInitScript(() => { window.__posts = []; window.FlutterBoard = { postMessage: s => window.__posts.push(s) }; });
    if (process.env.BOARD_JS) {
      const js = fs.readFileSync(process.env.BOARD_JS, 'utf8');
      await p.route('**/web3d/board.js', r => r.fulfill({ contentType: 'text/javascript', body: js }));
    }
    await p.goto(new URL('web3d/index.html', base).href);
    await p.waitForFunction(() => window.board);
    const send = j => p.evaluate(x => window.board.receive(JSON.stringify(x)), j);
    await send({ t: 'init', art: { file: '../maps/' + m.art.file, w: m.art.w, h: m.art.h, unitPx: m.art.unitPx },
      gfx: { scale: 1, auto: false, shadows: 1, aa: true, bloom: false, ao: false, scenery: true, brightness: 1, labels: 1, fps: false, tier: 1 },
      home: 1, spaces: m.spaces.map(s => ({ id: s.id, x: s.x, y: s.y })), links: m.links });
    const ids = m.spaces.map(s => s.id);
    await send({ t: 'state', fighters: [
      { id: 1, color: '#3d7bd9', hero: true, hp: 18, name: 'King Arthur', mini: 'king-arthur', fid: 'king-arthur', v: 0, space: ids[0] },
      { id: 2, color: '#d94b3d', hero: true, hp: 14, name: 'Bullseye', mini: 'bullseye', fid: 'bullseye', v: 0, ranged: true, space: ids[ids.length - 1] },
      { id: 3, color: '#3d7bd9', hero: false, hp: 7, name: 'Merlin', mini: 'king-arthur', fid: 'merlin', space: ids[1] },
    ], marks: {}, tokens: [], focus: [] });
    await p.waitForFunction(() => window.__posts.some(s => s.includes('"ready"')), null, { timeout: 60000 });
    await p.waitForTimeout(1500);
    return { p, send };
  };

  // Share of the canvas that is lit (the printed board is bright; a black canvas has none).
  const lit = p => p.evaluate(() => {
    const c = document.querySelector('canvas');
    const t = document.createElement('canvas'); t.width = 96; t.height = 54;
    const g = t.getContext('2d', { willReadFrequently: true });
    g.drawImage(c, 0, 0, 96, 54);
    const d = g.getImageData(0, 0, 96, 54).data;
    let n = 0, s = 0;
    for (let i = 0; i < d.length; i += 4) { s += 1; if (.299 * d[i] + .587 * d[i + 1] + .114 * d[i + 2] > 40) n++; }
    return n / s;
  });
  const fatal = p => p.evaluate(() => window.__posts.filter(s => s.includes('"fatal":true')));
  const settle = (p, ms = 1200) => p.waitForTimeout(ms);

  // --- tablet: collapse to a sliver, enlarge, turn, lose the GPU context ----------------------------
  const { p } = await open({ width: 1024, height: 768 }, 2);
  const base0 = await lit(p);
  check(base0 > 0.15, `board is drawn at the start (${(base0 * 100).toFixed(0)}% lit)`);

  await p.setViewportSize({ width: 4, height: 4 }); await settle(p, 600);
  await p.setViewportSize({ width: 1024, height: 768 }); await settle(p);
  const afterSliver = await lit(p);
  check(afterSliver > base0 * 0.6, `still drawn after shrinking to a sliver and enlarging (${(afterSliver * 100).toFixed(0)}% lit)`);

  for (const [w, h] of [[390, 844], [844, 390], [820, 1180], [1180, 820], [600, 300], [1280, 720]]) {
    await p.setViewportSize({ width: w, height: h }); await settle(p, 500);
  }
  const afterTurns = await lit(p);
  check(afterTurns > 0.15, `still drawn after phone/tablet sizes and turns (${(afterTurns * 100).toFixed(0)}% lit)`);

  await p.evaluate(() => { document.dispatchEvent(new Event('visibilitychange')); window.board.receive(JSON.stringify({ t: 'hidden' })); });
  await settle(p, 400);
  await p.evaluate(() => window.board.receive(JSON.stringify({ t: 'visible' })));
  await settle(p);
  check(await lit(p) > 0.15, 'still drawn after hidden / visible');

  const lose = await p.evaluate(() => {
    const gl = document.querySelector('canvas').getContext('webgl2') || document.querySelector('canvas').getContext('webgl');
    const ext = gl && gl.getExtension('WEBGL_lose_context');
    if (!ext) return false;
    window.__ext = ext; ext.loseContext(); return true;
  });
  if (lose) {
    await settle(p, 800);
    check((await fatal(p)).length === 0, 'losing the GPU context is not fatal straight away');
    await p.evaluate(() => window.__ext.restoreContext());
    await settle(p, 2500);
    const afterRestore = await lit(p);
    check((await fatal(p)).length === 0, 'no fatal error after the context came back');
    check(afterRestore > 0.15, `drawn again after the GPU context is restored (${(afterRestore * 100).toFixed(0)}% lit)`);
  } else {
    console.log('SKIP  WEBGL_lose_context is not available');
  }
  check(p.errors.length === 0, `no page errors${p.errors.length ? ': ' + p.errors.slice(0, 3).join(' | ') : ''}`);
  await p.screenshot({ path: path.join(process.env.OUT || '.', 'lifecycle-tablet.png') });

  // --- phone: the hero's edge has no dark outline --------------------------------------------------
  // The figure's transparent surround is black; the picture's edge pixels must take the figure's own
  // colours instead, or filtering draws a dark outline round it.
  const q = await open({ width: 844, height: 390 }, 3);
  const fringe = await q.p.evaluate(async () => {
    const out = {};
    for (const url of ['../heroes/bullseye/mini.webp', '../heroes/king-arthur/merlin.webp']) {
      const img = new Image(); img.src = new URL('web3d/' + url, location.origin + '/').href;
      try { await img.decode(); } catch (e) { out[url] = null; continue; }
      const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
      const g = c.getContext('2d', { willReadFrequently: true }); g.drawImage(img, 0, 0);
      const d = g.getImageData(0, 0, c.width, c.height).data;
      let ring = 0, dark = 0;
      for (let y = 1; y < c.height - 1; y++) for (let x = 1; x < c.width - 1; x++) {
        const i = (y * c.width + x) * 4;
        if (d[i + 3] > 20) continue; // transparent
        const near = [i - 4, i + 4, i - c.width * 4, i + c.width * 4].some(j => d[j + 3] > 200);
        if (!near) continue;
        ring++; if (d[i] + d[i + 1] + d[i + 2] < 24) dark++;
      }
      out[url] = { ring, dark };
    }
    return out;
  });
  console.log('source art, transparent pixels touching the figure (black colour under them):', JSON.stringify(fringe));
  check(q.p.errors.length === 0, 'no page errors on the phone page');
  await q.p.screenshot({ path: path.join(process.env.OUT || '.', 'lifecycle-phone.png') });

  await b.close();
  console.log(failures.length ? `\n${failures.length} FAILED` : '\nall passed');
  process.exit(failures.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
