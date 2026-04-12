#!/bin/bash
# Run Claude Code inside a microsandbox microVM
# Usage: ./run/msb-claude.sh [claude args...]
# Requires: msb installed on host, KVM enabled
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Ensure msb server is running (poll for readiness, not sleep)
if ! msb ls &>/dev/null; then
    echo "Starting microsandbox server..."
    msb server start --detach --listen 127.0.0.1
    for _i in $(seq 1 15); do
        msb ls &>/dev/null && break
        sleep 1
    done
    msb ls &>/dev/null || { echo "msb server failed to start" >&2; exit 1; }
fi

# Forward API keys that are set
MSB_ENV=()
[[ -n "${ANTHROPIC_API_KEY:-}" ]]  && MSB_ENV+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
[[ -n "${OPENAI_API_KEY:-}" ]]     && MSB_ENV+=(-e "OPENAI_API_KEY=${OPENAI_API_KEY}")
[[ -n "${GEMINI_API_KEY:-}" ]]     && MSB_ENV+=(-e "GEMINI_API_KEY=${GEMINI_API_KEY}")

exec msb run "${MSB_ENV[@]}" "$IMAGE" -- claude "$@"
