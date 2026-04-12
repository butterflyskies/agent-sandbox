#!/bin/bash
# Build claude-sandbox OCI image with cache mounts
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-claude-sandbox}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-}"

ARGS=(
    --tag "${IMAGE_NAME}:${IMAGE_TAG}"
    --file Containerfile
)

# Registry-backed cache (set REGISTRY to enable, e.g. ghcr.io/butterflyskies/claude-sandbox)
if [[ -n "$REGISTRY" ]]; then
    ARGS+=(
        --cache-from="${REGISTRY}:buildcache"
        --cache-to="${REGISTRY}:buildcache"
    )
fi

echo "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
podman build "${ARGS[@]}" .

echo ""
echo "Done. Run with:"
echo "  podman run -it --rm -e ANTHROPIC_API_KEY ${IMAGE_NAME}:${IMAGE_TAG}"
