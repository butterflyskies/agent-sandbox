#!/bin/bash
# Run Claude Code inside a microsandbox microVM
# Usage: ./run/msb-claude.sh [claude args...]
#
# Requires: msb server running (msb server start)
# The image must be pulled first: msb pull claude-sandbox
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="${IMAGE:-claude-sandbox}"
HOME_VOL="${HOME_VOL:-${ROOT_DIR}/home}"

# Ensure msb server is running
if ! msb ls &>/dev/null; then
    echo "Starting microsandbox server..."
    msb server start --detach
    sleep 2
fi

# Run Claude Code in a microVM sandbox
exec msb run "$IMAGE" -- claude "$@"
