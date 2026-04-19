#!/bin/bash
# Run Claude Code in a sandboxed container
# Usage: ./run/claude.sh [claude args...]
set -euo pipefail
source "$(dirname "$0")/common.sh"

exec "$RUNTIME" run "${RUNTIME_ARGS[@]}" "$IMAGE" "$@"
