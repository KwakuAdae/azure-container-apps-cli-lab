#!/usr/bin/env bash
# Step 3: Container Apps environment + the website container app (first revision: v1).
#   ./scripts/03-create-app.sh [tag]      (default v1)
source "$(dirname "$0")/config.sh"
require ACR_LOGIN_SERVER IDENTITY_ID
TAG="${1:-v1}"

step "Container Apps environment ${ENVIRONMENT} (~2-3 minutes)"
WORKSPACE_ID="$(az monitor log-analytics workspace show -g "$RESOURCE_GROUP" -n "$LOG_WORKSPACE" --query customerId -o tsv)"
WORKSPACE_KEY="$(az monitor log-analytics workspace get-shared-keys -g "$RESOURCE_GROUP" -n "$LOG_WORKSPACE" --query primarySharedKey -o tsv)"
az containerapp env create \
  --name "$ENVIRONMENT" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
  --logs-destination log-analytics \
  --logs-workspace-id "$WORKSPACE_ID" --logs-workspace-key "$WORKSPACE_KEY" \
  --output none

step "Container app ${APP_NAME} from ${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${TAG}"
az containerapp create \
  --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --environment "$ENVIRONMENT" \
  --image "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${TAG}" \
  --user-assigned "$IDENTITY_ID" \
  --registry-server "$ACR_LOGIN_SERVER" --registry-identity "$IDENTITY_ID" \
  --ingress external --target-port 8080 \
  --cpu 0.25 --memory 0.5Gi \
  --min-replicas 0 --max-replicas 5 \
  --scale-rule-name http-concurrency --scale-rule-type http --scale-rule-http-concurrency 20 \
  --revisions-mode multiple --revision-suffix "$TAG" \
  --env-vars "APP_VERSION=${TAG}" \
  --output none

# Pin all production traffic to this revision. New revisions then start with 0% traffic,
# which is what makes blue/green releases possible (step 4).
az containerapp ingress traffic set --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" \
  --revision-weight "${APP_NAME}--${TAG}=100" --output none

FQDN="$(az containerapp show -n "$APP_NAME" -g "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv)"
save APP_URL "https://${FQDN}"
echo ""
echo "✅ ${APP_URL}"
echo "   (with min-replicas 0, the first request after idle takes a few seconds: a cold start)"
