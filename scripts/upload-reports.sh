#!/usr/bin/env bash
set -euo pipefail

# Laster opp en rapportmappe til felles Blob Storage.
# Sti i lagringen: <container>/<TEAM>/<prosjekt>/<tidspunkt>/
#
# Krever at du er logget inn (az login, eller azure/login i GitHub Actions) og har
# rollen Storage Blob Data Contributor på containeren.
#
# Bruk: upload-reports.sh zap-output/<prosjekt>/<tidspunkt>

SRC="${1:?Bruk: upload-reports.sh <rapportmappe, f.eks. zap-output/minapp/2026-10-08T10-00-00Z>}"
: "${ZAP_STORAGE_ACCOUNT:?Mangler ZAP_STORAGE_ACCOUNT}"
: "${ZAP_STORAGE_CONTAINER:=zap-reports}"
: "${TEAM:?Mangler TEAM (brukes som øverste mappe i felles lagring)}"

if [[ ! -d "$SRC" ]]; then
  echo "Fant ikke rapportmappen: $SRC" >&2
  exit 1
fi

PROJECT="$(basename "$(dirname "$SRC")")"
TS="$(basename "$SRC")"
DEST_PATH="${TEAM}/${PROJECT}/${TS}"

echo "Laster opp ${SRC} til ${ZAP_STORAGE_ACCOUNT}/${ZAP_STORAGE_CONTAINER}/${DEST_PATH}"
az storage blob upload-batch \
  --auth-mode login \
  --account-name "$ZAP_STORAGE_ACCOUNT" \
  --destination "$ZAP_STORAGE_CONTAINER" \
  --destination-path "$DEST_PATH" \
  --source "$SRC" \
  --only-show-errors \
  --output none
echo "Opplasting ferdig"
