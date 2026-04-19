#!/bin/bash
# Drop into a zsh shell in the sandbox
# Usage: ./run/shell.sh
set -euo pipefail
source "$(dirname "$0")/common.sh"

exec "$RUNTIME" run "${RUNTIME_ARGS[@]}" --entrypoint zsh "$IMAGE"
