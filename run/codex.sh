#!/bin/bash
# Run OpenAI Codex in a sandboxed container
# Usage: ./run/codex.sh [codex args...]
set -euo pipefail
source "$(dirname "$0")/common.sh"

exec "$RUNTIME" run "${RUNTIME_ARGS[@]}" --entrypoint codex "$IMAGE" "$@"
