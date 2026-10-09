import { test } from '@playwright/test';

test('generate authenticated traffic via ZAP proxy', async ({ page }) => {
  const baseUrl = process.env.PLAYWRIGHT_BASE_URL;
  if (!baseUrl) {
    throw new Error('Missing PLAYWRIGHT_BASE_URL env var.');
  }

  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });

  // Override/disable by setting PLAYWRIGHT_SSO_REGEX to empty.
  const ssoRegexRaw = process.env.PLAYWRIGHT_SSO_REGEX ?? 'login\\.test\\.idporten\\.no|testid\\.test\\.idporten\\.no';
  if (ssoRegexRaw) {
    const ssoRegex = new RegExp(ssoRegexRaw);
    const url = page.url();
    if (ssoRegex.test(url)) {
      throw new Error(`Not authenticated – ended up at SSO: ${url}`);
    }
  }

  console.log('Authenticated traffic generated, URL:', page.url());
  await page.waitForTimeout(Number(process.env.PLAYWRIGHT_TRAFFIC_WAIT_MS || 8000));
});
