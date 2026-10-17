#!/usr/bin/env bash
# Shared settings for every step. Override any value by exporting it before running a script.
set -euo pipefail

export LOCATION="${LOCATION:-eastus}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aca-lab}"
export ENVIRONMENT="${ENVIRONMENT:-cae-aca-lab}"          # Container Apps environment
export APP_NAME="${APP_NAME:-website}"
export LOG_WORKSPACE="${LOG_WORKSPACE:-log-aca-lab}"
export IDENTITY_NAME="${IDENTITY_NAME:-id-aca-lab-acrpull}"
export IMAGE_REPO="website"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_ENV="${ROOT_DIR}/.lab-env"

# Values created in step 1 (the unique registry name, identity ID, app URL) are saved here
touch "$LAB_ENV"
# shellcheck disable=SC1090
source "$LAB_ENV"

save() {   # save NAME VALUE → remembered for later steps
  grep -v "^export $1=" "$LAB_ENV" > "${LAB_ENV}.tmp" || true
  echo "export $1=\"$2\"" >> "${LAB_ENV}.tmp"
  mv "${LAB_ENV}.tmp" "$LAB_ENV"
  export "$1=$2"
  echo "   $1=$2"
}

require() {
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      echo "❌ ${name} is not set. Run the earlier steps first (see README)." >&2
      exit 1
    fi
  done
}

step() { echo ""; echo "▶ $*"; }
