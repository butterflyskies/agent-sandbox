#!/bin/bash
# Build agent-sandbox OCI image with cache mounts
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-agent-sandbox}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
RUNTIME="${CONTAINER_RUNTIME:-podman}"

echo "Building ${IMAGE_NAME}:${IMAGE_TAG} with ${RUNTIME}..."
"$RUNTIME" build --tag "${IMAGE_NAME}:${IMAGE_TAG}" --file Containerfile --layers .

echo ""
echo "Done. Run with:"
echo "  ${RUNTIME} run -it --rm -e ANTHROPIC_API_KEY ${IMAGE_NAME}:${IMAGE_TAG}"
