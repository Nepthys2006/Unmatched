// Device profiles for the Full Screen help. Playwright's own iPad profiles send the "iPad" user agent,
// which is NOT what an iPad does by default (iPadOS 13+ pretends to be a Mac: "Macintosh" plus touch).
// So the default iPad behaviour has its own custom WebKit profile, and a real Mac (no touch) is
// included to prove it is not mistaken for an iPad.
import { defineConfig, devices } from '@playwright/test';

const macUa = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';

/** Each profile says who it is, so the tests know what to expect. */
const profile = (name, expect, use) => ({ name, metadata: { expect }, use });

const ipadDesktopMode = (viewport) => ({
  ...devices['iPad (gen 7)'],
  browserName: 'webkit',
  userAgent: macUa, // what iPadOS 13+ sends by default
  hasTouch: true,
  isMobile: false,
  viewport,
  // navigator.maxTouchPoints is 5 on an iPad and 0 on a Mac; Playwright can't set it, so the page is told.
  // (A page script runs before the app, like the real value being there from the start.)
});

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.mjs',
  timeout: 90_000,
  expect: { timeout: 20_000 },
  retries: process.env.CI ? 1 : 0,
  workers: 2,
  reporter: [['list']],
  use: { baseURL: process.env.E2E_BASE ?? 'http://localhost:8099/', trace: 'retain-on-failure' },
  webServer: [
    { command: 'node serve.mjs ../build/web 8099', url: 'http://localhost:8099/', reuseExistingServer: !process.env.CI },
    // A build that opens straight into a match (see music.spec.mjs).
    { command: 'node serve.mjs ../build/web_match 8098', url: 'http://localhost:8098/', reuseExistingServer: !process.env.CI },
  ],
  projects: [
    profile('iPhone portrait', { device: 'iphone', help: 'IPHONE', rotate: true, phone: true }, { ...devices['iPhone 13'] }),
    profile('iPhone landscape', { device: 'iphone', help: 'IPHONE', rotate: false, phone: true }, { ...devices['iPhone 13 landscape'] }),
    profile('iPad gen 7 portrait', { device: 'ipad', help: 'IPAD', rotate: false }, { ...devices['iPad (gen 7)'] }),
    profile('iPad gen 7 landscape', { device: 'ipad', help: 'IPAD', rotate: false }, { ...devices['iPad (gen 7) landscape'] }),
    profile('iPad Pro 11 portrait', { device: 'ipad', help: 'IPAD', rotate: false }, { ...devices['iPad Pro 11'] }),
    profile('iPad Pro 11 landscape', { device: 'ipad', help: 'IPAD', rotate: false }, { ...devices['iPad Pro 11 landscape'] }),
    profile('iPad default desktop-mode portrait', { device: 'ipad', help: 'IPAD', rotate: false, desktopModeTouch: 5 }, ipadDesktopMode({ width: 820, height: 1180 })),
    profile('iPad default desktop-mode landscape', { device: 'ipad', help: 'IPAD', rotate: false, desktopModeTouch: 5 }, ipadDesktopMode({ width: 1180, height: 820 })),
    profile('real Mac (no touch)', { device: 'mac', help: null, rotate: false }, {
      ...devices['Desktop Safari'],
      userAgent: macUa,
      hasTouch: false,
      viewport: { width: 1280, height: 800 },
    }),
    profile('Pixel portrait', { device: 'android', help: null, rotate: true, phone: true }, { ...devices['Pixel 7'] }),
    profile('Pixel landscape', { device: 'android', help: null, rotate: false, phone: true }, { ...devices['Pixel 7 landscape'] }),
    profile('Desktop Chrome', { device: 'windows', help: null, rotate: false }, { ...devices['Desktop Chrome'] }),
  ],
});
