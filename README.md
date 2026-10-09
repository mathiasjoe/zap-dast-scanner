# ZAP-skanning: blueprint for API og web

Selvstendig mappe som et team kopierer inn i sitt repo. Den gir:

- **Ett skann = én fersk ZAP-container.** Ingen server å drifte, ingen delt tilstand mellom team.
- **Skannet er beskrevet i YAML** (ZAP Automation Framework), ikke i kode. Teamet tilpasser planen.
- **Samme kommando lokalt og i CI.** GitHub Actions-workflows følger med, og et eksempel for Azure DevOps.
- **Felles lagring av rapporter** i Azure Blob Storage, med sti `<team>/<prosjekt>/<tidspunkt>/`.

```
plans/zap-api.yaml            ZAP-plan for API-skann (OpenAPI-import + bearer-token)
plans/zap-web.yaml            ZAP-plan for web-skann (venter på innlogget trafikk, spider, aktivt skann)
scripts/run-api.sh            Kjører API-skannet
scripts/run-web.sh            Kjører web-skannet (starter ZAP, kjører Playwright, venter på ZAP)
scripts/upload-reports.sh     Laster opp en rapportmappe til felles lagring
scripts/wait-for-zap.js       Venter til ZAP-proxyen svarer (brukes av web-skannet)
playwright/                   Innlogging og trafikkgenerering for web-skannet
.github/workflows/            Workflows for GitHub Actions
pipelines/                    Eksempel for Azure DevOps
azure/                        Engangsoppsett av felles lagring
legacy/                       Den gamle API-drevne varianten. Ikke i bruk, kan slettes.
```

## Forutsetninger

- Docker (lokalt: Docker Desktop)
- For web-skann: Node.js 20+ og `npm install` i denne mappen
- For opplasting til felles lagring: Azure CLI og `az login`

## Kom i gang lokalt

```bash
cp .env.example .env    # fyll inn
```

API-skann:

```bash
bash scripts/run-api.sh
```

Web-skann (første gang: `npm install && npx playwright install chromium`):

```bash
bash scripts/run-web.sh
```

Rapporter havner i `zap-output/<prosjekt>/<tidspunkt>/zap-report.html` og `.json`.
Skriptet avslutter med exit-kode 1 hvis det er funn på nivået i `ZAP_FAIL_ON` eller høyere.

### Hva skjer i API-skannet

1. Runneren henter et ferskt token fra `TOKEN_URL` med `TOKEN_BASIC_AUTH`.
2. ZAP starter med `plans/zap-api.yaml`. Token legges inn som `Authorization`-header på alle forespørsler.
3. OpenAPI-spec importeres, alle endepunkter skannes aktivt, rapport skrives, ZAP avslutter.

### Hva skjer i web-skannet

1. ZAP starter med `plans/zap-web.yaml` og venter i en delay-jobb.
2. Playwright logger inn (`playwright/global-setup.ts`, utenom ZAP) og sender app-trafikk gjennom ZAP-proxyen (`playwright/auth-traffic.spec.ts`). ZAP plukker opp sesjonscookiene.
3. Runneren signaliserer at trafikken er ferdig. ZAP spiderer, kjører AJAX-spider og aktivt skann, skriver rapport og avslutter.

Innloggingen i `global-setup.ts` er en mal. Hvert team fyller inn stegene for sin app og legger
testbruker-data i `.env` lokalt og som secrets i CI. Sett `PLAYWRIGHT_HEADED=1` for å se nettleseren.

## I GitHub Actions

1. Kopier `.github/workflows/zap-api.yml` og/eller `zap-web.yml` til `.github/workflows/` i repoet.
   Ligger blueprinten i en undermappe, sett `ZAP_DIR` øverst i workflowen.
2. Legg inn variabler og secrets under Settings → Secrets and variables → Actions:

   | Type | Navn | Brukes av |
   |---|---|---|
   | variabel | `TEAM` | begge |
   | variabel | `API_PROJECT`, `API_BASE`, `OPENAPI_SPEC_URL`, `TOKEN_URL` | API |
   | secret | `TOKEN_BASIC_AUTH` | API |
   | variabel | `WEB_PROJECT`, `WEB_TARGET`, `PLAYWRIGHT_BASE_URL` | web |
   | secret | det innloggingen trenger, f.eks. `TEST_USER_PID` | web |
   | variabel | `ZAP_FAIL_ON` (valgfri) | begge |
   | variabel | `ZAP_STORAGE_ACCOUNT` (valgfri, slår på felles lagring) | begge |
   | secret | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | felles lagring |

3. Trykk «Run workflow» under Actions, eller vent på den ukentlige kjøringen.

Rapporten ligger alltid som artifact på kjøringen, og i felles lagring hvis `ZAP_STORAGE_ACCOUNT` er satt.
Ikke kjør aktive skann på pull requests. De tar lang tid og belaster testmiljøet.

## Felles lagring i Azure

Engangsoppsett, gjøres av den som eier Azure-ressursene:

```bash
ZAP_STORAGE_ACCOUNT=<globalt unikt navn> bash azure/setup-storage.sh
```

Skriptet lager ressursgruppe, storage account, container `zap-reports` uten anonym tilgang,
soft delete, lifecycle-policy (cool etter 90 dager, slettes etter 365), en app-registrering som
GitHub Actions logger inn som via OIDC, og en Entra-gruppe for lesetilgang. Det skriver ut
verdiene som skal inn i GitHub.

Per repo som skal laste opp:

```bash
bash azure/add-github-repo.sh <github-org> <repo>
```

Lesetilgang: legg folk i Entra-gruppen `zap-report-readers`. Rapportene åpnes i Azure-portalen
eller Storage Explorer under `zap-reports/<team>/<prosjekt>/<tidspunkt>/`.

Utviklere som vil laste opp fra egen PC setter `ZAP_STORAGE_ACCOUNT` i `.env`, kjører `az login`
og trenger Storage Blob Data Contributor på containeren.

## Tilpasse planene

Planene i `plans/` er vanlige YAML-filer. Det vanligste å endre:

- **Scope.** `urls` i context bestemmer hva som skannes. Alt under URL-en er med, ingenting annet.
  Legg til `excludePaths` for ting som ikke skal røres. ID-porten og Altinn-plattformen er delt
  infrastruktur og skal aldri skannes aktivt fra et teams pipeline.
- **Regler.** `policyDefinition.rules` slår av eller justerer enkeltregler. DOM XSS (40026) er av
  fordi den starter en nettleser per test og ga OOM i Docker.
- **Kjente falske positiver.** Legg til en `alertFilter`-jobb før rapporten. Da er teamets triage
  versjonert sammen med planen.
- **Varighet.** `maxDuration` på spider-jobbene og `maxScanDurationInMins` på aktivt skann.
  Web-skann bør være kortere enn sesjonslevetiden til appen, ellers fortsetter ZAP uautentisert.
- **SARIF.** Fjern kommentaren på rapport-jobben med `sarif-json` for å laste opp til GitHub code scanning.

Dokumentasjon: https://www.zaproxy.org/docs/desktop/addons/automation-framework/

## Notater

- ZAP kjører som egen bruker i containeren. Runneren gjør rapportmappen skrivbar for alle før start.
- Web-skannet eksponerer ZAP-proxyen kun på `127.0.0.1:${ZAP_PORT}` på maskinen som kjører skannet.
- `legacy/` inneholder den gamle varianten som styrte ZAP via API fra Node-skript. Den fungerer
  fortsatt mot en ZAP-daemon, men vedlikeholdes ikke.
