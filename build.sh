#!/bin/bash
# Build claude-sandbox OCI image with cache mounts
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-claude-sandbox}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-}"

ARGS=(
    --tag "${IMAGE_NAME}:${IMAGE_TAG}"
    --file Containerfile
    --layers
)

# Registry-backed cache (set REGISTRY to enable, e.g. ghcr.io/butterflyskies/claude-sandbox)
if [[ -n "$REGISTRY" ]]; then
    ARGS+=(
        --cache-from="${REGISTRY}-cache"
        --cache-to="${REGISTRY}-cache"
    )
fi

echo "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
if [[ -n "$REGISTRY" ]]; then
    # Registry cache is best-effort — fall back to local-only on auth/push failure
    if ! podman build "${ARGS[@]}" . 2>&1; then
        echo ""
        echo "Registry cache failed (likely token scope). Retrying without registry cache..."
        podman build \
            --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
            --file Containerfile \
            --layers \
            .
    fi
else
    podman build "${ARGS[@]}" .
fi

echo ""
echo "Done. Run with:"
echo "  podman run -it --rm -e ANTHROPIC_API_KEY ${IMAGE_NAME}:${IMAGE_TAG}"
