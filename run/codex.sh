#!/bin/bash
# Run OpenAI Codex in a sandboxed container
# Usage: ./run/codex.sh [codex args...]
set -euo pipefail
source "$(dirname "$0")/common.sh"

exec podman run "${PODMAN_ARGS[@]}" \
    --entrypoint codex \
    -e OPENAI_API_KEY \
    "$IMAGE" "$@"
