#!/usr/bin/env bash
set -euo pipefail

# ZAP web-skann med Automation Framework (plans/zap-web.yaml) og Playwright-innlogging.
# Kjører likt lokalt og i CI. Krever docker, node og @playwright/test (npm install).
#
# Flyt: start ZAP med planen (venter i delay-jobb) -> Playwright logger inn og sender
# app-trafikk gjennom ZAP-proxyen -> runneren lager traffic-done -> ZAP spiderer og
# skanner aktivt -> rapport.
#
# Nødvendige variabler (fra .env eller miljøet):
#   WEB_PROJECT, WEB_TARGET, PLAYWRIGHT_BASE_URL (+ det innloggingen i playwright/global-setup.ts trenger)
# Valgfrie:
#   TEAM, ZAP_FAIL_ON, ZAP_STORAGE_ACCOUNT, ZAP_IMAGE, ZAP_DOCKER_MEMORY, ZAP_PORT,
#   PLAYWRIGHT_CONFIG, PLAYWRIGHT_TRAFFIC_SPEC, PLAYWRIGHT_STORAGE_STATE, PLAYWRIGHT_HEADED

ZAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ZAP_DIR"

if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env"
  set +a
fi

: "${WEB_PROJECT:?Mangler WEB_PROJECT (navn på appen, brukes i rapportstien)}"
: "${WEB_TARGET:?Mangler WEB_TARGET (base-URL som skal skannes)}"
: "${PLAYWRIGHT_BASE_URL:?Mangler PLAYWRIGHT_BASE_URL (URL det logges inn på)}"
: "${ZAP_FAIL_ON:=high}"
: "${ZAP_IMAGE:=zaproxy/zap-stable}"
: "${ZAP_DOCKER_MEMORY:=4g}"
: "${ZAP_PORT:=8080}"
: "${PLAYWRIGHT_CONFIG:=playwright/playwright.config.ts}"
: "${PLAYWRIGHT_TRAFFIC_SPEC:=playwright/auth-traffic.spec.ts}"
: "${PLAYWRIGHT_STORAGE_STATE:=playwright/auth.json}"
ZAP_URL="http://127.0.0.1:${ZAP_PORT}"
ZAP_CONTAINER="zap-web-$$"
export ZAP_FAIL_ON ZAP_URL PLAYWRIGHT_STORAGE_STATE

TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
OUT_DIR="zap-output/${WEB_PROJECT}/${TS}"
mkdir -p "$OUT_DIR"
chmod a+w "$OUT_DIR"                       # ZAP kjører som egen bruker i containeren
export ZAP_REPORT_DIR="/zap/wrk/${OUT_DIR}"

cleanup() {
  docker rm -f "$ZAP_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starter ZAP (${ZAP_IMAGE}) på ${ZAP_URL}, rapport til ${OUT_DIR}"
docker run -d --name "$ZAP_CONTAINER" --memory "$ZAP_DOCKER_MEMORY" \
  -p "127.0.0.1:${ZAP_PORT}:8080" \
  -v "${ZAP_DIR}/plans:/zap/wrk/plans:ro" \
  -v "${ZAP_DIR}/zap-output:/zap/wrk/zap-output" \
  -e WEB_TARGET -e ZAP_REPORT_DIR -e ZAP_FAIL_ON \
  "$ZAP_IMAGE" zap.sh -cmd -host 0.0.0.0 -port 8080 \
    -config api.disablekey=true \
    -config "api.addrs.addr.name=.*" \
    -config api.addrs.addr.regex=true \
    -autorun /zap/wrk/plans/zap-web.yaml >/dev/null

node scripts/wait-for-zap.js

echo "Logger inn og sender trafikk gjennom ZAP-proxyen (${PLAYWRIGHT_TRAFFIC_SPEC})"
npx playwright test --config="${PLAYWRIGHT_CONFIG}" "${PLAYWRIGHT_TRAFFIC_SPEC}"

touch "${OUT_DIR}/traffic-done"
echo "Trafikk ferdig. ZAP fortsetter med spider og aktivt skann."
docker logs -f "$ZAP_CONTAINER" || true
status="$(docker wait "$ZAP_CONTAINER")"
rm -f "${OUT_DIR}/traffic-done"

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "ZAP_REPORT_DIR=${OUT_DIR}" >> "$GITHUB_ENV"
fi

if [[ -n "${ZAP_STORAGE_ACCOUNT:-}" ]]; then
  bash scripts/upload-reports.sh "$OUT_DIR"
fi

case "$status" in
  0) echo "Ferdig: ingen funn på nivå ${ZAP_FAIL_ON} eller høyere. Rapport: ${OUT_DIR}" ;;
  1) echo "Ferdig: funn på nivå ${ZAP_FAIL_ON} eller høyere. Rapport: ${OUT_DIR}" >&2 ;;
  2) echo "Ferdig med advarsler fra planen (se loggen over). Rapport: ${OUT_DIR}"; status=0 ;;
  *) echo "ZAP avsluttet med exit-kode ${status}" >&2 ;;
esac
exit "$status"
