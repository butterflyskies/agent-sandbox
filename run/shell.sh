#!/bin/bash
# Drop into a zsh shell in the sandbox
# Usage: ./run/shell.sh
set -euo pipefail
source "$(dirname "$0")/common.sh"

exec podman run "${PODMAN_ARGS[@]}" \
    --entrypoint zsh \
    -e ANTHROPIC_API_KEY \
    -e OPENAI_API_KEY \
    -e GEMINI_API_KEY \
    "$IMAGE"
