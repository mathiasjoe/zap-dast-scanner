import * as path from 'path';
import { defineConfig } from '@playwright/test';

// Playwright-oppsett for ZAP-blueprinten.
// Testene (auth-traffic.spec.ts) sender all trafikk gjennom ZAP-proxyen.
// Innloggingen (global-setup.ts) går IKKE gjennom proxyen, så ID-porten havner aldri i ZAP.
//
// Kjører headless som standard. Sett PLAYWRIGHT_HEADED=1 for å se nettleseren lokalt.

const ZAP_URL = process.env.ZAP_URL || 'http://127.0.0.1:8080';
const HEADED = process.env.PLAYWRIGHT_HEADED === '1';

export default defineConfig({
  testDir: __dirname,
  globalSetup: require.resolve('./global-setup'),

  use: {
    proxy: { server: ZAP_URL },
    storageState: process.env.PLAYWRIGHT_STORAGE_STATE || path.join(__dirname, 'auth.json'),
    ignoreHTTPSErrors: true,
    headless: !HEADED,
    launchOptions: {
      args: ['--disable-http2', '--disable-quic'],
    },
  },
});
