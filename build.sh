#!/bin/bash
# Build agent-sandbox OCI image with cache mounts
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-agent-sandbox}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-}"
RUNTIME="${CONTAINER_RUNTIME:-podman}"

BASE_ARGS=(
    --tag "${IMAGE_NAME}:${IMAGE_TAG}"
    --file Containerfile
    --layers
)

echo "Building ${IMAGE_NAME}:${IMAGE_TAG} with ${RUNTIME}..."

if [[ -n "$REGISTRY" ]]; then
    CACHE_ARGS=(
        --cache-from="${REGISTRY}-cache"
        --cache-to="${REGISTRY}-cache"
    )
    # Registry cache is best-effort — fall back to local-only on auth/push failure
    if ! "$RUNTIME" build "${BASE_ARGS[@]}" "${CACHE_ARGS[@]}" . 2>&1; then
        echo ""
        echo "WARNING: Registry cache failed (likely token scope). Retrying without registry cache..."
        "$RUNTIME" build "${BASE_ARGS[@]}" .
    fi
else
    "$RUNTIME" build "${BASE_ARGS[@]}" .
fi

echo ""
echo "Done. Run with:"
echo "  ${RUNTIME} run -it --rm -e ANTHROPIC_API_KEY ${IMAGE_NAME}:${IMAGE_TAG}"
