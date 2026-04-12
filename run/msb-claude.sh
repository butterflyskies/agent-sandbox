#!/bin/bash
# Run Claude Code inside a microsandbox microVM
# Usage: ./run/msb-claude.sh [claude args...]
# Requires: msb installed on host, KVM enabled
set -euo pipefail

IMAGE="${IMAGE:-agent-sandbox}"

if ! msb ls &>/dev/null; then
    echo "Starting microsandbox server..."
    msb server start --detach
    sleep 2
fi

exec msb run "$IMAGE" -- claude "$@"
