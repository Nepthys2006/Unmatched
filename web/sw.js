/* Unmatched service worker: makes the game open and play offline after the first visit.
 *
 * Flutter 3.4x no longer ships flutter_service_worker.js (the --pwa-strategy flag is gone), so the
 * app has its own small one. It only touches same-origin GET requests: the game's files. Calls to the
 * Supabase server (match sync, lobbies, accounts) are other origins and always go straight to the
 * network, so they are never cached and an offline match still syncs later through the app's own
 * match cache. Build with `flutter build web --release --no-web-resources-cdn` so CanvasKit is
 * served from this origin (and so cached) instead of from a CDN.
 *
 *  - install:  the shell is cached (page, bootstrap, manifest, icons).
 *  - fetch:    the game's own files (page, loader, app code, version, manifest) come from the NETWORK
 *              FIRST and fall back to the cache only when offline, so a new release is picked up on the
 *              next visit and a player is never left on an old build next to a newer one. Everything
 *              else (the engine, fonts, cards, audio) is cache first and refreshed in the background.
 *  - navigation while offline: the cached index.html.
 *  - every release stamps its own CACHE name (tool/stamp_sw.py), which deletes the previous
 *    release's caches, so the engine files can never be older than the app code.
 */
const CACHE = 'unmatched-__BUILD__';
// Files that decide which build the player runs.
const CORE = /(^|\/)(index\.html|flutter_bootstrap\.js|flutter\.js|main\.dart\.js|version\.json|manifest\.json|sw\.js)$/;
// Everything the first screen needs. Files that do not exist in a given build are skipped.
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/apple-touch-icon-180.png',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
  'canvaskit/skwasm.js',
  'canvaskit/skwasm.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      // One missing file must not stop the worker from installing.
      .then((cache) => Promise.all(SHELL.map((url) => cache.add(url).catch(() => undefined))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Other origins (the Supabase API, a CDN) are not ours to cache.
  if (url.origin !== self.location.origin) return;
  // Range requests (audio seeking) are answered by the network.
  if (req.headers.has('range')) return;

  const core = req.mode === 'navigate' || CORE.test(url.pathname) || url.pathname.endsWith('/');
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(req, { ignoreSearch: req.mode === 'navigate' });
      if (core) {
        // Network first; the copy kept for offline is replaced every time the network answers.
        try {
          const res = await fetch(req);
          if (res && res.ok && res.type === 'basic') cache.put(req, res.clone()).catch(() => undefined);
          return res;
        } catch (_) {
          if (cached) return cached;
          const page = (await cache.match('index.html')) || (await cache.match('./'));
          if (req.mode === 'navigate' && page) return page;
          return new Response('Offline', { status: 503, statusText: 'Offline', headers: { 'Content-Type': 'text/plain' } });
        }
      }
      const refresh = fetch(req)
        .then((res) => {
          if (res && res.ok && res.type === 'basic') cache.put(req, res.clone()).catch(() => undefined);
          return res;
        })
        .catch(() => undefined);
      if (cached) {
        // Serve what we have now, update it for next time.
        event.waitUntil(refresh);
        return cached;
      }
      const res = await refresh;
      if (res) return res;
      if (req.mode === 'navigate') {
        const page = (await cache.match('index.html')) || (await cache.match('./'));
        if (page) return page;
      }
      return new Response('Offline', { status: 503, statusText: 'Offline', headers: { 'Content-Type': 'text/plain' } });
    })(),
  );
});
