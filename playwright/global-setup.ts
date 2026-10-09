// ZAP-blueprint: Playwright global setup
//
// Mal for innlogging som lager/oppdaterer auth.json før ZAP-skannet.
// Hvert team tilpasser selectorer og testbruker for sin egen app.
//
// Merk
// - Innloggingen går IKKE gjennom ZAP-proxyen. Bare app-trafikken i auth-traffic.spec.ts gjør det.
// - Kjører headless som standard. Sett PLAYWRIGHT_HEADED=1 for å se nettleseren lokalt.

import * as path from 'path';
import { chromium, FullConfig } from '@playwright/test';

async function globalSetup(_config: FullConfig) {
  const baseUrl = process.env.PLAYWRIGHT_BASE_URL;
  if (!baseUrl) {
    throw new Error('Mangler PLAYWRIGHT_BASE_URL (URL til appen det skal logges inn på).');
  }

  const storageStatePath = process.env.PLAYWRIGHT_STORAGE_STATE || path.join(__dirname, 'auth.json');
  const headless = process.env.PLAYWRIGHT_HEADED !== '1';

  const browser = await chromium.launch({ headless });
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto(baseUrl);

  // ---- MAL FOR INNLOGGING ----
  // Bytt ut alt under med innloggingsstegene for din app.
  // Eksempel (Altinn TestID):
  // await page.getByRole('link', { name: 'TestID Lag din egen testbruker' }).click();
  // await page.getByRole('textbox', { name: /Personidentifikator/ }).fill(process.env.TEST_USER_PID!);
  // await page.getByRole('button', { name: 'Autentiser' }).click();
  // ...
  // ---- /MAL FOR INNLOGGING ----

  await page.waitForLoadState('networkidle');

  await context.storageState({ path: storageStatePath });

  await browser.close();
}

export default globalSetup;
