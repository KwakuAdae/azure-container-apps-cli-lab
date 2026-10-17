#!/usr/bin/env bash
# Call the production URL N times and count which version answered.
#   ./scripts/06-watch-versions.sh 40
source "$(dirname "$0")/config.sh"
require APP_URL
COUNT="${1:-40}"

echo ">> ${COUNT} requests to ${APP_URL}/version.json"
for _ in $(seq "$COUNT"); do
  curl -s --max-time 15 "${APP_URL}/version.json" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["version"], d["color"])' 2>/dev/null \
    || echo "error"
done | sort | uniq -c
