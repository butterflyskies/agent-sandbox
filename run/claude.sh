#!/bin/bash
# Run Claude Code in a sandboxed container
# Usage: ./run/claude.sh [claude args...]
set -euo pipefail
source "$(dirname "$0")/common.sh"

exec podman run "${PODMAN_ARGS[@]}" \
    -e ANTHROPIC_API_KEY \
    "$IMAGE" "$@"
