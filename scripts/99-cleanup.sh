#!/usr/bin/env bash
# Delete everything: all lab resources live in one resource group.
source "$(dirname "$0")/config.sh"

step "Deleting resource group ${RESOURCE_GROUP} (~3-5 minutes)"
az group delete --name "$RESOURCE_GROUP" --yes
rm -f "$LAB_ENV"
echo "✅ Done."
