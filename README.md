# ZAP-skanning: blueprint for API og web

Selvstendig mappe som et team kopierer inn i sitt repo. Den gir:

- **Ett skann = én fersk ZAP-container.** Ingen server å drifte, ingen delt tilstand mellom team.
- **Skannet er beskrevet i YAML** (ZAP Automation Framework), ikke i kode. Teamet tilpasser planen.
- **Samme kommando lokalt og i CI.** GitHub Actions-workflows følger med, og et eksempel for Azure DevOps.
- **Funnene havner i GitHub.** Rapporten lastes opp som SARIF til Security → Code scanning i teamets repo,
  og organisasjonens Security overview gir oversikten på tvers av team.

```
plans/zap-api.yaml            ZAP-plan for API-skann (OpenAPI-import + bearer-token)
plans/zap-web.yaml            ZAP-plan for web-skann (venter på innlogget trafikk, spider, aktivt skann)
scripts/run-api.sh            Kjører API-skannet
scripts/run-web.sh            Kjører web-skannet (starter ZAP, kjører Playwright, venter på ZAP)
scripts/wait-for-zap.js       Venter til ZAP-proxyen svarer (brukes av web-skannet)
scripts/sarif-for-github.sh   Skriver om SARIF-rapporten så GitHub code scanning godtar den (brukes av workflowene)
playwright/                   Innlogging og trafikkgenerering for web-skannet
.github/workflows/            Workflows for GitHub Actions
pipelines/                    Eksempel for Azure DevOps
```

## Forutsetninger

- Docker (lokalt: Docker Desktop)
- For web-skann: Node.js 20+ og `npm install` i denne mappen

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

Rapporter havner i `zap-output/<prosjekt>/<tidspunkt>/` som `zap-report.html`, `zap-report.json`
og `zap-report.sarif`. Skriptet avslutter med exit-kode 1 hvis det er funn på nivå high eller høyere.
Terskelen settes i `exitStatus`-jobben i planen.

### Hva skjer i API-skannet

1. Runneren henter et ferskt token fra `TOKEN_URL` med `TOKEN_BASIC_AUTH`.
2. ZAP starter med `plans/zap-api.yaml`. Token legges inn som `Authorization`-header på alle forespørsler.
3. OpenAPI-spec importeres, alle endepunkter skannes aktivt, rapporter skrives, ZAP avslutter.

### Hva skjer i web-skannet

1. ZAP starter med `plans/zap-web.yaml` og venter i en delay-jobb.
2. Playwright logger inn (`playwright/global-setup.ts`, utenom ZAP) og sender app-trafikk gjennom
   ZAP-proxyen (`playwright/auth-traffic.spec.ts`). ZAP plukker opp sesjonscookiene.
3. Runneren signaliserer at trafikken er ferdig. ZAP spiderer, kjører AJAX-spider og aktivt skann,
   skriver rapporter og avslutter.

Innloggingen i `global-setup.ts` er en mal. Hvert team fyller inn stegene for sin app og legger
testbruker-data i `.env` lokalt og som secrets i CI. Sett `PLAYWRIGHT_HEADED=1` for å se nettleseren.

## I GitHub Actions

1. Kopier `.github/workflows/zap-api.yml` og/eller `zap-web.yml` til `.github/workflows/` i repoet.
   Ligger blueprinten i en undermappe, sett `ZAP_DIR` øverst i workflowen.
2. Legg inn variabler og secrets under Settings → Secrets and variables → Actions:

   | Type | Navn | Brukes av |
   |---|---|---|
   | variabel | `API_PROJECT`, `API_BASE`, `OPENAPI_SPEC_URL`, `TOKEN_URL` | API |
   | secret | `TOKEN_BASIC_AUTH` | API |
   | variabel | `WEB_PROJECT`, `WEB_TARGET`, `PLAYWRIGHT_BASE_URL` | web |
   | secret | det innloggingen trenger, f.eks. `TEST_USER_PID` | web |

3. Trykk «Run workflow» under Actions, eller vent på den ukentlige kjøringen.

Ikke kjør aktive skann på pull requests. De tar lang tid og belaster testmiljøet.

### Funnene i Security-fanen

Workflowen laster opp `zap-report.sarif` med `github/codeql-action/upload-sarif`, etter at
`scripts/sarif-for-github.sh` har skrevet den om:

- **Ett funn per regel.** ZAP rapporterer samme feil én gang per adresse. Skriptet slår dem sammen,
  og adressene står som liste i meldingen, med angrep og bevis der ZAP har det. Listen kappes ved
  100 adresser, resten står i HTML-rapporten.
- **Pseudosti.** Code scanning krever at funn peker på en fil i repoet. Hvert funn får stien
  `dast/<regel-id>-<regelnavn>`. Den finnes ikke som fil, og det er greit.
- **Alvorlighetsgrad.** ZAPs risiko settes som `security-severity` på regelen, så GitHub viser
  High, Medium eller Low. Informational vises som Note.

Da får dere:

- Alle funn under **Security → Code scanning** i repoet, med beskrivelse, URL og løsningsforslag fra ZAP.
- **Dedup mellom kjøringer.** Et funn som allerede er åpent blir ikke opprettet på nytt, og funn som
  forsvinner lukkes automatisk.
- **Triage i GitHub.** Falske positiver avvises der, med begrunnelse, og holder seg avvist i senere kjøringer.
- **Oversikt på tvers av team** under organisasjonens Security → Overview.

API- og web-skann lastes opp med hver sin `category`, så de lever side om side. Opplastingen kjører
også når skannet feiler på funn.

Code scanning er gratis for offentlige repoer. Private repoer trenger GitHub Code Security
(tidligere GitHub Advanced Security) på organisasjonen.

HTML- og JSON-rapporten ligger i tillegg som artifact på hver kjøring.

## Tilpasse planene

Planene i `plans/` er vanlige YAML-filer. Det vanligste å endre:

- **Scope.** `urls` i context bestemmer hva som skannes. Alt under URL-en er med, ingenting annet.
  Legg til `excludePaths` for ting som ikke skal røres. ID-porten og Altinn-plattformen er delt
  infrastruktur og skal aldri skannes aktivt fra et teams pipeline.
- **Regler.** `policyDefinition.rules` slår av eller justerer enkeltregler. DOM XSS (40026) er av
  fordi den starter en nettleser per test og ga OOM i Docker.
- **Kjente falske positiver.** Avvis dem i Security-fanen, eller legg til en `alertFilter`-jobb før
  rapportene hvis de ikke skal i rapporten i det hele tatt.
- **Varighet.** `maxDuration` på spider-jobbene og `maxScanDurationInMins` på aktivt skann.
  Web-skann bør være kortere enn sesjonslevetiden til appen, ellers fortsetter ZAP uautentisert.
- **Feile eller ikke.** `errorLevel` i `exitStatus`-jobben styrer hvilket nivå som gir rød kjøring:
  `info`, `low`, `medium` eller `high`. Miljøvariabler virker ikke i den jobben, så verdien endres
  direkte i planen. Skal kjøringen aldri feile på funn, fjern jobben. Funnene havner i Security-fanen uansett.

Dokumentasjon: https://www.zaproxy.org/docs/desktop/addons/automation-framework/

## Notater

- Planene har `failOnWarning: true`. Et feilstavet parameter eller en ugyldig verdi stopper planen med
  en tydelig melding i loggen, i stedet for at ZAP skanner videre med feil oppsett.
- ZAP kjører som egen bruker i containeren. Runneren gjør rapportmappen skrivbar for alle før start.
- Web-skannet eksponerer ZAP-proxyen kun på `127.0.0.1:${ZAP_PORT}` på maskinen som kjører skannet.
- ZAP gir SARIF-rapporten sin egen filendelse. Runneren gir den fast navn `zap-report.sarif`
  så workflowen alltid finner den.
