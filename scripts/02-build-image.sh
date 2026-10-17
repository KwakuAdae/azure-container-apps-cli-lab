#!/usr/bin/env bash
# Step 2: Build the website image IN AZURE with ACR Tasks (no local Docker needed).
#   ./scripts/02-build-image.sh v1 blue
#   ./scripts/02-build-image.sh v2 green
#   ./scripts/02-build-image.sh v3 orange --local   # build with your own Docker instead
source "$(dirname "$0")/config.sh"
require ACR_NAME ACR_LOGIN_SERVER
TAG="${1:?usage: $0 <tag> [blue|green|orange] [--local]}"
COLOR="${2:-blue}"
BUILT="$(date -u +%Y-%m-%dT%H:%MZ)"

if [[ "${3:-}" == "--local" ]]; then
  step "Building locally and pushing ${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${TAG}"
  az acr login --name "$ACR_NAME"
  docker build --platform linux/amd64 \
    --build-arg APP_VERSION="$TAG" --build-arg APP_COLOR="$COLOR" --build-arg BUILD_TIME="$BUILT" \
    -t "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${TAG}" "${ROOT_DIR}/app"
  docker push "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${TAG}"
else
  step "Building ${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${TAG} (${COLOR}) with ACR Tasks"
  az acr build --registry "$ACR_NAME" \
    --image "${IMAGE_REPO}:${TAG}" --platform linux/amd64 \
    --build-arg APP_VERSION="$TAG" --build-arg APP_COLOR="$COLOR" --build-arg BUILD_TIME="$BUILT" \
    "${ROOT_DIR}/app"
fi

step "Tags in the registry"
az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_REPO" --output table
