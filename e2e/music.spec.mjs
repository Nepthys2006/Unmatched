// The background music must keep playing when buttons and cards are pressed: it must never jump
// back to the start. The browser's audio elements are watched: every write to `currentTime` (which is
// how a player restarts or seeks a track) and every play() is logged, then buttons are pressed.
//
// The menu test runs against build/web (DEMO build); the battle test against build/web_match, a build made with
//   flutter build web --release --dart-define=QUICKMATCH=blossom:2:alice:3 --no-web-resources-cdn --output build/web_match
// (served on port 8098 by the config).
import { expect, test } from '@playwright/test';

const spy = () => {
  window.__audio = [];
  const d = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'currentTime');
  Object.defineProperty(HTMLMediaElement.prototype, 'currentTime', {
    get() {
      return d.get.call(this);
    },
    set(v) {
      window.__audio.push({ kind: 'seek', to: v, from: d.get.call(this), src: (this.currentSrc || '').split('/').pop() });
      d.set.call(this, v);
    },
  });
  window.__els = new Set();
  const play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function () {
    window.__els.add(this);
    window.__audio.push({ kind: 'play', src: (this.currentSrc || this.src || '').split('/').pop() });
    return play.call(this);
  };
  window.__music = () => {
    // The audio elements the app made (they are never put in the page, so they are collected as they play).
    return [...window.__els].map((a) => ({ src: a.currentSrc.split('/').pop(), t: a.currentTime, paused: a.paused }));
  };
};

const nodes = (page) =>
  page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((e) => (e.getAttribute('aria-label') ?? e.textContent ?? '').trim()).filter(Boolean));

async function waitFor(page, re, timeout = 60_000) {
  await expect.poll(async () => (await nodes(page)).some((l) => re.test(l)), { timeout }).toBe(true);
}

/** A real mouse click in the middle of the button whose label matches. */
async function press(page, re, timeout = 15_000) {
  const box = await expect
    .poll(
      () =>
        page.evaluate((src) => {
          const rx = new RegExp(src, 'i');
          const el = [...document.querySelectorAll('flt-semantics[role="button"]')].find((e) => rx.test((e.getAttribute('aria-label') ?? e.textContent ?? '').trim()));
          if (!el) return null;
          const r = el.getBoundingClientRect();
          return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
        }, re.source),
      { timeout },
    )
    .not.toBeNull()
    .then(() =>
      page.evaluate((src) => {
        const rx = new RegExp(src, 'i');
        const el = [...document.querySelectorAll('flt-semantics[role="button"]')].find((e) => rx.test((e.getAttribute('aria-label') ?? e.textContent ?? '').trim()));
        const r = el.getBoundingClientRect();
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
      }, re.source),
    );
  await page.mouse.click(box.x, box.y);
}

test.use({ launchOptions: { args: ['--autoplay-policy=no-user-gesture-required'] } });

test.describe('background music keeps playing when things are pressed', () => {
  test('menu: pressing buttons never restarts the theme', async ({ page }, info) => {
    test.skip(info.project.name !== 'Desktop Chrome', 'the audio code is the same on every browser');
    await page.addInitScript(spy);
    await page.goto('/?semantics=1');
    await waitFor(page, /Play vs AI/i);
    // Let the theme get going and a few seconds in.
    await expect.poll(async () => (await page.evaluate(() => window.__music?.() ?? [])).some((a) => /theme|menu/.test(a.src) && !a.paused && a.t > 2), { timeout: 40_000 }).toBe(true);
    const before = await page.evaluate(() => window.__audio.length);
    const startedAt = await page.evaluate(() => window.__music().find((a) => /theme|menu/.test(a.src) && !a.paused)?.t);
    // Presses spaced further apart than the 2 s throttle, different buttons and the same one twice.
    const targets = [/^Match history/, /^Match history/, /^Active Players/, /^Full screen/, /^Settings/, /^Settings/];
    let last = startedAt;
    for (const t of targets) {
      await press(page, t);
      await page.waitForTimeout(2300);
      // Back out of whatever opened.
      await page.keyboard.press('Escape');
      await press(page, /^Back/, 1500).catch(() => undefined);
      await page.waitForTimeout(2300);
      const now = await page.evaluate(() => window.__music().find((a) => /theme|menu/.test(a.src) && !a.paused)?.t);
      expect(now, `the theme must still be playing after pressing ${t}`).toBeGreaterThan(last);
      last = now;
    }
    const events = (await page.evaluate(() => window.__audio)).slice(before);
    const restarts = events.filter((e) => e.kind === 'seek' && e.to < 1 && /theme|menu/.test(e.src));
    expect(restarts, `the music was sent back to the start: ${JSON.stringify(events)}`).toHaveLength(0);
    expect(events.filter((e) => e.kind === 'play' && /theme|menu/.test(e.src)), 'the theme was started again').toHaveLength(0);
  });
});

test.describe('in a match', () => {
  test.use({ baseURL: 'http://localhost:8098/' });

  test('battle: pressing buttons never restarts the battle theme', async ({ page }, info) => {
    test.skip(info.project.name !== 'Desktop Chrome', 'the audio code is the same on every browser');
    await page.addInitScript(spy);
    await page.goto('/?semantics=1');
    // The match is up (its first questions are Alice's size, then where the sidekicks go).
    await waitFor(page, /^Menu/i, 90_000);
    const battle = (a) => /battle/.test(a.src) && !a.paused;
    await expect.poll(async () => (await page.evaluate(() => window.__music?.() ?? [])).some((a) => /battle/.test(a.src) && !a.paused && a.t > 2), { timeout: 60_000 }).toBe(true);
    const before = await page.evaluate(() => window.__audio.length);
    let last = await page.evaluate(() => window.__music().find((a) => /battle/.test(a.src) && !a.paused)?.t);
    expect(battle).toBeDefined();
    // Different buttons, and the same one again: the opening question, the pause menu over and over, the log, the cards.
    const steps = [/^BIG/, /^Menu/, /^Resume/, /^Menu/, /^Resume/, /^Game log/, /^Game log/, /^Identity cards/, /^Menu/, /^Resume/];
    let pressed = 0;
    for (const re of steps) {
      await press(page, re, 8000).then(() => pressed++, () => undefined);
      await page.waitForTimeout(2300);
      const now = await page.evaluate(() => window.__music().find((a) => /battle/.test(a.src) && !a.paused)?.t);
      expect(now, `the battle theme must still be playing after pressing ${re}`).toBeGreaterThan(last);
      last = now;
    }
    expect(pressed, 'most of the buttons were really pressed').toBeGreaterThanOrEqual(6);
    const events = (await page.evaluate(() => window.__audio)).slice(before);
    const restarts = events.filter((e) => e.kind === 'seek' && e.to < 1 && /battle/.test(e.src));
    expect(restarts, `the music was sent back to the start: ${JSON.stringify(events)}`).toHaveLength(0);
    expect(events.filter((e) => e.kind === 'play' && /battle/.test(e.src)), 'the battle theme was started again').toHaveLength(0);
  });
});
