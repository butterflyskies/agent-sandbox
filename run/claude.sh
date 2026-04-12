#!/bin/bash
# Run Claude Code in a sandboxed container
# Usage: ./run/claude.sh [claude args...]
#
# Expects ANTHROPIC_API_KEY in environment.
# Mounts the persistent home from ./home/ (create with skeleton/init.sh).
# Source repos go in ./home/dev/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="${IMAGE:-claude-sandbox}"
HOME_VOL="${HOME_VOL:-${ROOT_DIR}/home}"

if [[ ! -d "$HOME_VOL" ]]; then
    echo "No persistent home at $HOME_VOL"
    echo "Run ./skeleton/init.sh first, or set HOME_VOL to your volume path."
    exit 1
fi

exec podman run -it --rm \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --hostname claude-sandbox \
    -v "${HOME_VOL}:/home/agent:Z" \
    -e ANTHROPIC_API_KEY \
    "$IMAGE" "$@"
