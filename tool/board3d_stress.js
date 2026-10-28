// Stress test for the 3D board page (assets/web3d): hundreds of random messages, as a match and a
// player would send them, in any order: board states (fighters coming and going, health, pieces,
// attack types, marks, tokens), moves, hit effects, every camera move, drags, pinches, flicks,
// graphics settings (tier, AO, AA, bloom, shadows, resolution), taps, window resizes and malformed
// messages. Fails on any page error, an error the page reports, a stalled render loop, or
// geometries/textures that keep growing.
//
//   cd assets && python -m http.server 8765        (in another terminal)
//   npm i playwright && npx playwright install chromium
//   node tool/board3d_stress.js [map id] [rounds per phase] [seed] [base url]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const [mapId = 'hells-kitchen', rounds, seedArg, base = 'http://127.0.0.1:8765/'] = process.argv.slice(2);
const maps = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'assets', 'data', 'maps.json')));
const m = maps[mapId];
let seed = +(seedArg || 1);
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
const pick = a => a[Math.floor(rnd() * a.length)];
const int = (a, b) => a + Math.floor(rnd() * (b - a + 1));

(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 640, height: 300 }, deviceScaleFactor: 1 });
  const errors = [];
  p.on('pageerror', e => errors.push('pageerror: ' + e.message));
  p.on('console', c => { if (c.type() === 'error') errors.push('console: ' + c.text()); });
  // Stand in for the app's bridge, to see what the page reports (errors included).
  await p.addInitScript(() => { window.__posts = []; window.FlutterBoard = { postMessage: s => window.__posts.push(s) }; });
  await p.goto(new URL('web3d/index.html', base).href);
  await p.waitForFunction(() => window.board);
  const send = async j => {
    try { await p.evaluate(x => window.board.receive(JSON.stringify(x)), j); } catch (e) { errors.push(`receive ${j.t}: ${e.message}`); }
  };
  const ids = m.spaces.map(s => s.id);
  const gfx = () => ({
    scale: pick([0.5, 0.75, 1, 1.25, 1.5]), auto: rnd() < 0.7, shadows: int(0, 3), aa: rnd() < 0.7, bloom: rnd() < 0.6,
    ao: rnd() < 0.25, scenery: true, brightness: pick([0.6, 1, 1.6]), labels: pick([0.6, 1, 1.8]), fps: rnd() < 0.3, tier: int(0, 3),
  });
  await send({ t: 'init', art: { file: '../maps/' + m.art.file, w: m.art.w, h: m.art.h, unitPx: m.art.unitPx }, gfx: gfx(), home: 1,
    spaces: m.spaces.map(s => ({ id: s.id, x: s.x, y: s.y })), links: m.links });

  // Two players' worth of fighters: heroes with pieces, ranged and melee, a sidekick, a pack of
  // small ones, a big two-space one, and ones that come and go.
  const roster = [
    { id: 1, color: '#3d7bd9', hero: true, hp: 18, name: 'King Arthur', mini: 'king-arthur', fid: 'king-arthur', v: 0 },
    { id: 2, color: '#3d7bd9', hero: false, hp: 7, name: 'Merlin', mini: 'king-arthur', fid: 'merlin', ranged: true },
    { id: 3, color: '#d94b3d', hero: true, hp: 14, name: 'Bullseye', mini: 'bullseye', fid: 'bullseye', v: 0, ranged: true },
    { id: 4, color: '#d94b3d', hero: false, hp: 1, name: 'Outlaw 1', mini: 'robin-hood', fid: 'outlaws' },
    { id: 5, color: '#d94b3d', hero: false, hp: 1, name: 'Squirrel 1', mini: 'squirrel-girl', fid: 'squirrel', small: true },
    { id: 6, color: '#3d7bd9', hero: true, hp: 15, name: 'T. Rex', mini: 't-rex', fid: 't-rex', v: 0 },
    { id: 7, color: '#59e0ff', hero: true, hp: 7, name: 'Raptor 2', mini: 'raptors', fid: 'raptors', v: 1 },
  ];
  const where = new Map(roster.map(f => [f.id, pick(ids)]));
  const items = () => pick([[], [{ k: 'card', e: '🃏', t: 'BIG', c: '#f2c14e' }], [{ k: 'tokens', e: '🎯', t: 'AIM', n: int(0, 3), m: 3, c: '#e05a5a' }, { k: 'count', e: '🔥', t: 'HELLFIRE', n: int(0, 9) }]]);
  const state = () => {
    const alive = roster.filter(() => rnd() < 0.85);
    return {
      t: 'state',
      fighters: alive.map(f => ({ ...f, space: where.get(f.id), hp: Math.max(0, f.hp - int(0, 6)), ranged: f.ranged ? rnd() < 0.9 : rnd() < 0.1,
        ...(f.id === 1 || f.id === 3 ? { items: items() } : {}), ...(f.id === 6 && rnd() < 0.5 ? { tail: pick(ids) } : {}),
        ...(f.small ? { off: [rnd() - 0.5, rnd() - 0.5] } : {}), color: rnd() < 0.05 ? '#c57bff' : f.color })),
      marks: {
        select: alive.filter(() => rnd() < 0.3).map(f => f.id), targets: alive.filter(() => rnd() < 0.2).map(f => f.id),
        spaces: ids.filter(() => rnd() < 0.1), edges: m.links.filter(() => rnd() < 0.05), harmful: rnd() < 0.5,
        pendingFighter: rnd() < 0.2 ? pick(alive.map(f => f.id).concat([1])) : null, pendingSpace: rnd() < 0.2 ? pick(ids) : null,
        subject: rnd() < 0.2 ? 1 : null, preview: rnd() < 0.3 ? [pick(ids), pick(ids), pick(ids)] : null,
      },
      tokens: [
        ...(rnd() < 0.5 ? [{ kind: 'fog', space: pick(ids) }] : []), ...(rnd() < 0.5 ? [{ kind: 'trap', space: pick(ids) }] : []),
        ...(rnd() < 0.5 ? [{ kind: 'insight', space: pick(ids) }, { kind: 'insight', space: pick(ids) }] : []),
        ...(rnd() < 0.5 ? [{ kind: 'shadow', space: pick(ids) }] : []), ...(rnd() < 0.5 ? [{ kind: 'foot', a: m.links[0][0], b: m.links[0][1] }] : []),
      ],
      focus: rnd() < 0.3 ? [1, 3] : [],
    };
  };

  const ops = [
    () => send(state()),
    () => send(state()),
    () => { const f = pick(roster); const path = [where.get(f.id), pick(ids), pick(ids)]; where.set(f.id, path[2]); return send({ t: 'move', id: f.id, path, ms: int(0, 900) }); },
    () => send({ t: 'fx', id: pick(roster).id, text: pick(['-3', '+1', 'BLOCKED', '💥']), color: pick(['#ff5b4e', '#9bea5c']), sparks: rnd() < 0.5, ms: int(0, 900) }),
    () => send({ t: 'shake' }),
    () => send({ t: 'cam', op: pick(['fit', 'zoom', 'push', 'pull', 'turn', 'tilt']), k: pick([0.8, 1.25]), a: pick(ids), b: pick(ids), ms: int(0, 900) }),
    () => send({ t: 'drag', dx: rnd() - 0.5, dy: rnd() - 0.5 }),
    () => send({ t: 'orbit', dx: (rnd() - 0.5) * 0.3, dy: (rnd() - 0.5) * 0.3 }),
    () => send({ t: 'pinch', k: pick([0.5, 0.9, 1.1, 2, 4]), a: (rnd() - 0.5) * 0.4, ...(rnd() < 0.6 ? { fx: rnd(), fy: rnd() } : {}) }),
    () => send({ t: 'fling', vx: (rnd() - 0.5) * 6, vy: (rnd() - 0.5) * 6 }),
    () => send({ t: 'pick', x: rnd(), y: rnd() }),
    () => send({ t: 'gfx', gfx: gfx() }),
    () => p.setViewportSize({ width: int(320, 960), height: int(200, 540) }),
    () => send({ t: pick(['nonsense', 'state']), junk: true }), // malformed
    () => p.evaluate(() => window.board.receive('{broken json')),
  ];

  const roundsN = +(rounds || 200);
  const memory = [];
  for (let phase = 0; phase < 3; phase++) {
    for (let i = 0; i < roundsN; i++) {
      await pick(ops)();
      if (rnd() < 0.3) await p.waitForTimeout(int(0, 60));
    }
    // settle: same settings, one state, then read the counts
    await p.setViewportSize({ width: 640, height: 300 });
    // (the governor off, so it can't be halfway through turning an effect off when we count)
    await send({ t: 'gfx', gfx: { scale: 1, auto: false, shadows: 2, aa: true, bloom: true, ao: false, scenery: true, brightness: 1, labels: 1, fps: false, tier: 2 } });
    await send({ t: 'state', fighters: roster.map(f => ({ ...f, space: where.get(f.id) })), marks: {}, tokens: [], focus: [] });
    await p.waitForTimeout(2500);
    const s = await p.evaluate(() => window.board.stats());
    memory.push(s);
  }
  // The loop is still drawing: a change gets a new frame.
  const before = (await p.evaluate(() => window.board.stats())).frames;
  await send({ t: 'cam', op: 'turn', a: 0.5, ms: 300 });
  await p.waitForTimeout(1500);
  const after = (await p.evaluate(() => window.board.stats())).frames;

  console.log(JSON.stringify({ memory: memory.map(s => ({ geometries: s.geometries, textures: s.textures, pieces: s.pieces })), framesDrawn: after - before }));
  // Once every figure has loaded (phase 1), the same board must take the same memory.
  const grow = Math.max(memory[2].geometries, memory[1].geometries) - memory[0].geometries;
  const growT = Math.max(memory[2].textures, memory[1].textures) - memory[0].textures;
  const posts = await p.evaluate(() => window.__posts);
  for (const raw of posts) { const msg = JSON.parse(raw); if (msg.t === 'error') errors.push('page reported: ' + msg.msg); }
  const fails = [...errors];
  if (after - before < 1) fails.push('render loop stalled');
  if (grow > 4 || growT > 4) fails.push(`memory keeps growing: geometries +${grow}, textures +${growT} after phase 1`);
  console.log(fails.length ? 'FAIL\n' + fails.slice(0, 20).join('\n') : 'PASS');
  await b.close();
  process.exit(fails.length ? 1 : 0);
})();
