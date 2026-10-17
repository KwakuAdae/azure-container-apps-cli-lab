#!/usr/bin/env bash
# Step 4: Release a new version as a NEW REVISION that gets 0% of production traffic,
# with a "green" label so you can test it on its own URL first.
#   ./scripts/04-release.sh v2
source "$(dirname "$0")/config.sh"
require ACR_LOGIN_SERVER
TAG="${1:?usage: $0 <tag>}"
NEW_REVISION="${APP_NAME}--${TAG}"

step "Creating revision ${NEW_REVISION} (production traffic stays where it is)"
az containerapp update --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" \
  --image "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${TAG}" \
  --revision-suffix "$TAG" \
  --set-env-vars "APP_VERSION=${TAG}" \
  --output none

step "Labelling it 'green' (moves the label if it was on an older revision)"
az containerapp revision label add --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" \
  --label green --revision "$NEW_REVISION" --yes --output none

az containerapp ingress traffic show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --output table

DOMAIN="$(az containerapp env show -n "$ENVIRONMENT" -g "$RESOURCE_GROUP" --query properties.defaultDomain -o tsv)"
echo ""
echo "✅ ${NEW_REVISION} is live on its test URL only:"
echo "   https://${APP_NAME}---green.${DOMAIN}"
echo "   Production (${APP_URL:-https://<app-url>}) is unchanged."
echo "   When happy:  ./scripts/05-shift-traffic.sh ${TAG} 20   (then 50, then 100)"
