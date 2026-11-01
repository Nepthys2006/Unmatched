// Browser tests of the built web app (`flutter build web --release --dart-define=DEMO=true
// --no-web-resources-cdn`, DEMO so the menu opens without an account). Flutter draws on a canvas, so
// everything is found through the accessibility tree, switched on with ?semantics=1 (and the debug
// panel with ?debug=1).
import { expect, test } from '@playwright/test';

const OPEN = '/?semantics=1&debug=1';

test.beforeEach(async ({ page }, info) => {
  const m = info.project.metadata.expect;
  // An iPad in its default (desktop) mode has maxTouchPoints 5; Playwright can't set it, so it is set here,
  // before any page script runs, like the real value being there from the start.
  if (m.desktopModeTouch) {
    await page.addInitScript((n) => Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: () => n }), m.desktopModeTouch);
  }
  page.on('pageerror', (e) => test.info().annotations.push({ type: 'pageerror', description: String(e) }));
});

/** Every label the accessibility tree has right now. */
const labels = (page) =>
  page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((e) => e.getAttribute('aria-label') ?? e.textContent ?? '').filter(Boolean));

const hasLabel = async (page, re) => (await labels(page)).some((l) => re.test(l));

async function waitLabel(page, re, timeout = 30_000) {
  await expect.poll(() => hasLabel(page, re), { timeout, message: `waiting for ${re}` }).toBe(true);
}

/** Where the button whose label starts with this text is (case does not matter), or null. */
const buttonAt = (page, text) =>
  page.evaluate((src) => {
    const el = [...document.querySelectorAll('flt-semantics[role="button"]')].find((e) =>
      (e.getAttribute('aria-label') ?? e.textContent ?? '').trim().toLowerCase().startsWith(src.toLowerCase()),
    );
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, text);

/** A real click on the button with this label (the semantics nodes sit exactly over what is drawn). */
async function tapLabel(page, text, timeout = 15_000) {
  await expect.poll(() => buttonAt(page, text), { timeout, message: `waiting for the "${text}" button` }).not.toBeNull();
  let at = await buttonAt(page, text);
  // A long panel (the debug panel) scrolls: wheel over it until the button is on screen.
  const { width, height } = page.viewportSize();
  for (let i = 0; i < 20 && at.y > height - 8; i++) {
    await page.mouse.move(width / 2, height / 2);
    await page.mouse.wheel(0, Math.max(200, at.y - height / 2));
    await page.waitForTimeout(250);
    at = await buttonAt(page, text);
  }
  await page.mouse.click(at.x, at.y);
}

async function openApp(page, url = OPEN) {
  await page.goto(url);
  // The menu is up (DEMO build: no sign-in) or, on an iPhone / iPad, the help that opens over it.
  await waitLabel(page, /Play vs AI|FULL SCREEN ON/i, 60_000);
}

const portraitPhone = (info) => info.project.metadata.expect.phone && info.project.metadata.expect.rotate;

test.describe('the page itself', () => {
  test('manifest, icons and meta tags are in place', async ({ page, request }) => {
    await page.goto('/');
    const manifestHref = await page.locator('link[rel="manifest"]').getAttribute('href');
    expect(manifestHref).toBeTruthy();
    const manifest = await (await request.get(`/${manifestHref}`)).json();
    expect(manifest.display).toBe('standalone');
    expect(manifest.orientation).toBe('any');
    expect(manifest.name).toBe('Unmatched');
    expect(manifest.short_name).toBe('Unmatched');
    expect(manifest.theme_color).toBe(manifest.background_color);
    const sizes = manifest.icons.map((i) => `${i.sizes}${i.purpose === 'maskable' ? ' maskable' : ''}`);
    expect(sizes).toEqual(expect.arrayContaining(['192x192', '512x512', '192x192 maskable', '512x512 maskable']));
    for (const icon of manifest.icons) expect((await request.get(`/${icon.src}`)).ok(), icon.src).toBeTruthy();

    // iPhone and iPad touch icons, all three sizes, and the files exist.
    for (const size of ['180x180', '167x167', '152x152']) {
      const href = await page.locator(`link[rel="apple-touch-icon"][sizes="${size}"]`).getAttribute('href');
      expect(href, `apple-touch-icon ${size}`).toBeTruthy();
      const res = await request.get(`/${href}`);
      expect(res.ok(), href).toBeTruthy();
      expect(res.headers()['content-type']).toContain('image/png');
    }
    const meta = (name) => page.locator(`meta[name="${name}"]`).getAttribute('content');
    expect(await meta('apple-mobile-web-app-capable')).toBe('yes');
    expect(await meta('apple-mobile-web-app-status-bar-style')).toBe('black-translucent');
    expect(await meta('apple-mobile-web-app-title')).toBe('Unmatched');
    expect(await meta('viewport')).toContain('viewport-fit=cover');
    expect(await page.title()).toBe('Unmatched');
    // No pull to refresh, no double tap zoom.
    const css = await page.evaluate(() => {
      const s = getComputedStyle(document.body);
      return { overscroll: s.overscrollBehaviorY, touch: s.touchAction };
    });
    // (Older WebKit has no overscroll-behavior at all and reports nothing.)
    expect([undefined, 'none']).toContain(css.overscroll);
    // Flutter's engine sets touch-action: none (stricter: no zoom gestures at all); our CSS asks for manipulation.
    expect(['manipulation', 'none']).toContain(css.touch);
  });
});

test.describe('who the device is, and who sees the help', () => {
  test('the debug panel names the device and the help appears only on an iPhone or iPad', async ({ page }, info) => {
    const m = info.project.metadata.expect;
    test.skip(portraitPhone(info), 'a phone held upright shows "turn your phone" over the app');
    await openApp(page);
    if (m.help) {
      await waitLabel(page, new RegExp(`FULL SCREEN ON ${m.help}`, 'i'));
      // The other title is not there.
      expect(await hasLabel(page, new RegExp(`FULL SCREEN ON ${m.help === 'IPHONE' ? 'IPAD' : 'IPHONE'}`, 'i'))).toBe(false);
      await tapLabel(page, 'Got it');
      await expect.poll(() => hasLabel(page, /FULL SCREEN ON/i)).toBe(false);
      // Restart (reload): remembered.
      await page.reload();
      await waitLabel(page, /Play vs AI|FULL SCREEN ON/i, 40_000);
      await page.waitForTimeout(3500);
      expect(await hasLabel(page, /FULL SCREEN ON/i), 'not shown again after GOT IT').toBe(false);
    } else {
      await page.waitForTimeout(4500);
      expect(await hasLabel(page, /FULL SCREEN ON/i), `${m.device} never gets the help`).toBe(false);
    }
    // What the page itself says it is (the debug panel's live values).
    await tapLabel(page, 'DEBUG');
    await waitLabel(page, /DEBUG PANEL/i);
    const all = await labels(page);
    const at = all.findIndex((l) => l === 'device kind');
    expect(at, 'device kind row').toBeGreaterThanOrEqual(0);
    expect(all[at + 1]).toBe(m.device);
  });

  test('the debug panel\'s self-check passes every rule', async ({ page }, info) => {
    test.skip(portraitPhone(info) || info.project.metadata.expect.device !== 'windows', 'runs once, on desktop');
    await openApp(page);
    await tapLabel(page, 'DEBUG');
    await waitLabel(page, /DEBUG PANEL/i);
    await tapLabel(page, 'Run self-check');
    await waitLabel(page, /\d+ PASS · 0 FAIL/);
    expect(await hasLabel(page, /FAIL {2}/)).toBe(false);
  });
});

test.describe('orientation and window size', () => {
  test('"turn your phone" shows on a phone held upright, never on an iPad', async ({ page }, info) => {
    const m = info.project.metadata.expect;
    await page.goto(OPEN);
    await page.waitForTimeout(2500);
    const overlay = await page.locator('#rotate').evaluate((e) => getComputedStyle(e).display !== 'none');
    expect(overlay, `#rotate on ${info.project.name}`).toBe(Boolean(m.rotate));
    if (m.device === 'ipad') expect(await hasLabel(page, /TURN YOUR PHONE/i)).toBe(false);
    expect(await hasLabel(page, /MAKE THIS WINDOW LARGER/i), 'normal sizes are big enough').toBe(false);
  });

  test('iPad Split View and Slide Over widths: a clear message, then back to the game', async ({ page }, info) => {
    test.skip(!/desktop-mode landscape/.test(info.project.name), 'one iPad profile is enough');
    await openApp(page);
    await tapLabel(page, 'Got it').catch(() => undefined);
    for (const [w, h] of [[507, 768], [320, 768]]) {
      await page.setViewportSize({ width: w, height: h });
      await waitLabel(page, /MAKE THIS WINDOW LARGER/i, 10_000);
      expect(await hasLabel(page, /TURN YOUR PHONE/i), 'an iPad is not a phone').toBe(false);
    }
    await page.setViewportSize({ width: 1180, height: 820 });
    await expect.poll(() => hasLabel(page, /MAKE THIS WINDOW LARGER/i)).toBe(false);
    await waitLabel(page, /Play vs AI|FULL SCREEN ON/i, 15_000); // the menu (or the help over it) is still there
    const errors = info.annotations.filter((a) => a.type === 'pageerror');
    expect(errors, errors.map((e) => e.description).join('\n')).toHaveLength(0);
  });
});

test.describe('the Full Screen button', () => {
  test('does what the device needs', async ({ page }, info) => {
    const m = info.project.metadata.expect;
    test.skip(portraitPhone(info), 'a phone held upright shows "turn your phone" over the app');
    await openApp(page);
    await page.waitForTimeout(2500);
    // Close the automatic help first (iPhone / iPad).
    if (m.help) await tapLabel(page, 'Got it');
    await expect.poll(() => hasLabel(page, /FULL SCREEN ON/i)).toBe(false);
    await tapLabel(page, 'Full screen');
    await page.waitForTimeout(1500);
    const entered = await page.evaluate(() => Boolean(document.fullscreenElement || document.webkitFullscreenElement));
    const dialog = await hasLabel(page, /FULL SCREEN ON/i);
    if (m.device === 'iphone') {
      expect(dialog, 'iPhone: always the Home Screen help').toBe(true);
      expect(entered).toBe(false);
    } else if (m.device === 'ipad') {
      expect(entered || dialog, 'iPad: real full screen, or the help when Safari refuses').toBe(true);
    } else {
      expect(dialog, `${m.device}: no dialog`).toBe(false);
    }
  });
});

test.describe('offline', () => {
  test('after one visit the app opens with the network off', async ({ page, context }, info) => {
    test.skip(portraitPhone(info), 'a phone held upright shows "turn your phone" over the app');
    test.skip(!/(Desktop Chrome|iPhone landscape|desktop-mode landscape)/.test(info.project.name), 'the service worker is the same everywhere');
    await openApp(page);
    // The service worker installs and takes over; one more visit fills its cache while it controls the page.
    await page.evaluate(() => navigator.serviceWorker.ready.then(() => true));
    await expect.poll(() => page.evaluate(() => Boolean(navigator.serviceWorker.controller)), { timeout: 30_000 }).toBe(true).catch(async () => {
      await page.reload();
    });
    await page.reload();
    await waitLabel(page, /Play vs AI|FULL SCREEN ON/i, 40_000);
    const cached = await page.evaluate(async () => {
      const names = await caches.keys();
      let n = 0;
      for (const name of names) n += (await (await caches.open(name)).keys()).length;
      return n;
    });
    expect(cached, 'files cached for offline').toBeGreaterThan(5);
    await context.setOffline(true);
    await page.reload();
    await waitLabel(page, /Play vs AI|FULL SCREEN ON/i, 40_000);
    await context.setOffline(false);
  });
});
