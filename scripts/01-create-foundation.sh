#!/usr/bin/env bash
# Step 1: Resource group, Log Analytics, Azure Container Registry, and a managed identity
# that is allowed to pull from the registry.
source "$(dirname "$0")/config.sh"

step "Subscription: $(az account show --query '[name, id]' -o tsv | tr '\t' ' ')"

step "Registering resource providers (one-time per subscription; safe to repeat)"
for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do
  az provider register --namespace "$ns" --wait
  echo "   ${ns}: registered"
done

step "Resource group ${RESOURCE_GROUP} in ${LOCATION}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

step "Log Analytics workspace ${LOG_WORKSPACE} (container logs go here)"
az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE" \
  --location "$LOCATION" --retention-time 30 --output none

step "Azure Container Registry (name must be globally unique)"
if [[ -z "${ACR_NAME:-}" ]]; then
  save ACR_NAME "acracalab$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
fi
az acr create --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" \
  --sku Basic --admin-enabled false --location "$LOCATION" --output none
save ACR_LOGIN_SERVER "$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"

step "User-assigned managed identity ${IDENTITY_NAME} with AcrPull on the registry"
az identity create --resource-group "$RESOURCE_GROUP" --name "$IDENTITY_NAME" \
  --location "$LOCATION" --output none
save IDENTITY_ID "$(az identity show -g "$RESOURCE_GROUP" -n "$IDENTITY_NAME" --query id -o tsv)"
PRINCIPAL_ID="$(az identity show -g "$RESOURCE_GROUP" -n "$IDENTITY_NAME" --query principalId -o tsv)"
ACR_ID="$(az acr show --name "$ACR_NAME" --query id -o tsv)"

# A brand-new identity can take a few seconds to appear in Microsoft Entra ID
GRANTED=false
for attempt in 1 2 3 4 5 6; do
  if az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
       --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID" \
       --output none 2>/dev/null; then
    GRANTED=true
    echo "   AcrPull granted"
    break
  fi
  echo "   identity not visible yet, retrying in 10s (${attempt}/6)..."
  sleep 10
done
if [[ "$GRANTED" != true ]]; then
  echo "❌ Could not create the AcrPull role assignment. You need Owner or User Access Administrator." >&2
  exit 1
fi

echo ""
echo "✅ Foundation ready. Next: ./scripts/02-build-image.sh v1 blue"
