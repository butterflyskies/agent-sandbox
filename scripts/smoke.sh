#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-agent-sandbox}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_REF="${IMAGE}:${IMAGE_TAG}"
PODMAN_USERNS="${PODMAN_USERNS-keep-id:uid=1000,gid=1000}"

just build

podman run --rm "$IMAGE_REF" true
podman run --rm "$IMAGE_REF" shell -lc 'echo shell-ok'
podman run --rm "$IMAGE_REF" zsh -lc 'echo zsh-ok'

if ! podman run --rm "$IMAGE_REF" --version; then
    echo "warning: Claude version check failed; this may require auth or a different Claude CLI behavior" >&2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
userns_args=()
if [[ -n "$PODMAN_USERNS" ]]; then
    userns_args=(--userns="$PODMAN_USERNS")
fi

podman run --rm \
    "${userns_args[@]}" \
    -v "$tmp:/home/agent/dev/work:Z" \
    "$IMAGE_REF" \
    sh -lc 'id && touch /home/agent/dev/work/probe'

actual="$(stat -c '%u:%g' "$tmp/probe")"
expected="$(id -u):$(id -g)"
if [[ "$actual" != "$expected" ]]; then
    echo "UID/GID smoke failed: expected $expected, got $actual" >&2
    exit 1
fi

echo "Podman smoke checks passed"
