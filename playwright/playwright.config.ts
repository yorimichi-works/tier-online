import { defineConfig, devices } from '@playwright/test';

const PORT = 8973;
const BASE_URL = `http://localhost:${PORT}`;

export default defineConfig({
  testDir: './tests',
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 2,
  retries: 1,
  reporter: [
    ['list'],
    ['html', { outputFolder: '../artifacts/playwright-report', open: 'never' }],
  ],
  outputDir: '../artifacts/test-results',
  use: {
    baseURL: BASE_URL,
    trace: 'retain-on-failure',
    video: 'off',
  },
  webServer: {
    command: `node spa-server.mjs ../build/web-debug ${PORT}`,
    url: BASE_URL,
    reuseExistingServer: true,
    timeout: 30_000,
  },
  projects: [
    {
      name: 'desktop-1440x1000',
      use: { viewport: { width: 1440, height: 1000 } },
    },
    {
      name: 'laptop-1280x800',
      use: { viewport: { width: 1280, height: 800 } },
    },
    {
      name: 'tablet-768x1024',
      use: { viewport: { width: 768, height: 1024 } },
    },
    {
      name: 'mobile-390x844',
      use: { viewport: { width: 390, height: 844 } },
    },
    {
      name: 'mobile-small-360x800',
      use: { viewport: { width: 360, height: 800 } },
    },
  ],
});
