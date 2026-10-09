const ZAP = process.env.ZAP_URL || 'http://127.0.0.1:8080';

async function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitForZap({ retries = 60, delayMs = 5000 } = {}) {
  for (let i = 1; i <= retries; i++) {
    try {
      const res = await fetch(`${ZAP}/JSON/core/view/version/`);
      if (res.ok) {
        const data = await res.json();
        console.log(`ZAP is ready (${data.version})`);
        return;
      }
    } catch {
      // ignore and retry
    }

    console.log(`Waiting for ZAP... (${i}/${retries})`);
    await sleep(delayMs);
  }

  throw new Error(`ZAP did not start in time: ${ZAP}`);
}

waitForZap().catch((err) => {
  console.error(err?.stack || String(err));
  process.exit(1);
});
