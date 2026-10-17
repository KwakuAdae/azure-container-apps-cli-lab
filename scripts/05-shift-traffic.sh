#!/usr/bin/env bash
# Step 5: Move production traffic to a revision gradually (canary), then all of it.
#   ./scripts/05-shift-traffic.sh v2 20     # 20% to v2, 80% to the revision serving most traffic now
#   ./scripts/05-shift-traffic.sh v2 100    # cut over
#   ./scripts/05-shift-traffic.sh v1 100    # instant rollback
source "$(dirname "$0")/config.sh"
TAG="${1:?usage: $0 <tag> <percent>}"
PERCENT="${2:?usage: $0 <tag> <percent>}"
TARGET="${APP_NAME}--${TAG}"

# The revision currently receiving the most traffic (other than the target) keeps the rest
CURRENT="$(az containerapp ingress traffic show -n "$APP_NAME" -g "$RESOURCE_GROUP" \
  --query "sort_by([?revisionName!='${TARGET}' && weight > \`0\`], &weight)[-1].revisionName" -o tsv)"

if [[ "$PERCENT" -ge 100 || -z "$CURRENT" ]]; then
  WEIGHTS=("${TARGET}=100")
else
  WEIGHTS=("${TARGET}=${PERCENT}" "${CURRENT}=$((100 - PERCENT))")
fi

step "Traffic: ${WEIGHTS[*]}"
az containerapp ingress traffic set --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" \
  --revision-weight "${WEIGHTS[@]}" --output none
az containerapp ingress traffic show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --output table

echo ""
echo "Check the split:  ./scripts/06-watch-versions.sh 40"
