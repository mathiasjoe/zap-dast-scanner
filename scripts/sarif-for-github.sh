#!/usr/bin/env bash
set -euo pipefail

# Skriver om ZAPs SARIF-rapport så GitHub code scanning godtar den.
#
# GitHub krever at hvert funn peker på en fil i repoet, mens ZAP setter den fulle URL-en
# som "fil". Dette skriptet gir hvert funn en pseudosti, dast/<host>/<path>, og legger
# URL-en øverst i meldingen. Dermed blir funnene unike per endepunkt og regel, og
# deduplisering mellom kjøringer fungerer.
#
# Bruk: sarif-for-github.sh <zap-report.sarif>   (filen skrives om på stedet, krever jq)

FILE="${1:?Bruk: sarif-for-github.sh <sarif-fil>}"
if [[ ! -f "$FILE" ]]; then
  echo "Fant ikke SARIF-fil: $FILE" >&2
  exit 1
fi
command -v jq >/dev/null || { echo "jq mangler" >&2; exit 1; }

TMP="$(mktemp)"
jq '
  def pseudo_path:
    sub("^[a-zA-Z]+://"; "")        # fjern scheme
    | sub("[?#].*$"; "")            # fjern query og fragment
    | gsub("[^A-Za-z0-9._/-]"; "_") # bare trygge tegn i stien
    | gsub("/+"; "/")
    | sub("/+$"; "")
    | "dast/" + .;

  .runs[] |= (
    .results = [ (.results // [])[]
      | (
          [ (.locations // [])[]?.physicalLocation.artifactLocation.uri // empty
            | select(test("^[a-zA-Z]+://")) ] | .[0]
        ) as $url
      | .locations = [ (.locations // [])[]
          | (.physicalLocation.artifactLocation.uri // "") as $u
          | if ($u | test("^[a-zA-Z]+://")) then
              .physicalLocation.artifactLocation.uri = ($u | pseudo_path)
              | .physicalLocation.artifactLocation.uriBaseId = "%SRCROOT%"
              | .physicalLocation.region = ((.physicalLocation.region // {}) + {startLine: 1})
              | .properties = ((.properties // {}) + {url: $u})
            else . end
        ]
      | if $url then
          .message.text = ($url + "\n\n" + (.message.text // ""))
        else . end
    ]
  )
' "$FILE" > "$TMP"
mv "$TMP" "$FILE"
echo "SARIF tilpasset code scanning: $FILE ($(jq '[.runs[].results | length] | add // 0' "$FILE") funn)"
