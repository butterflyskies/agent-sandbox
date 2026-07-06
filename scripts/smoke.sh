#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-agent-sandbox}"
IMAGE_SSHD="${IMAGE_SSHD:-agent-sandbox-sshd}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_REF="${IMAGE}:${IMAGE_TAG}"
IMAGE_SSHD_REF="${IMAGE_SSHD}:${IMAGE_TAG}"
PODMAN_USERNS="${PODMAN_USERNS-keep-id:uid=1000,gid=1000}"

just build
just build-sshd

podman run --rm "$IMAGE_REF" true
podman run --rm "$IMAGE_REF" shell -lc 'echo shell-ok'
podman run --rm "$IMAGE_REF" zsh -lc 'echo zsh-ok'

if ! podman run --rm "$IMAGE_REF" --version; then
    echo "warning: Claude version check failed; this may require auth or a different Claude CLI behavior" >&2
fi

tmp="$(mktemp -d)"
home_tmp=""
trap 'rm -rf "$tmp" "$home_tmp"' EXIT
userns_args=()
if [[ -n "$PODMAN_USERNS" ]]; then
    userns_args=(--userns="$PODMAN_USERNS" --user agent)
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

home_tmp="$(mktemp -d)"
printf 'nodejs 0.0.0\n' > "$home_tmp/.tool-versions"
podman run --rm \
    "${userns_args[@]}" \
    -v "$home_tmp:/home/agent:Z" \
    "$IMAGE_REF" \
    sh -lc 'test -f "$HOME/.zshrc" && test -f "$HOME/.tool-versions" && command -v node >/dev/null'

if [[ ! -f "$home_tmp/.zshrc" || ! -f "$home_tmp/.tool-versions" ]]; then
    echo "Home template smoke failed: mounted home was not seeded" >&2
    exit 1
fi
if grep -q 'nodejs 0.0.0' "$home_tmp/.tool-versions"; then
    echo "Home template smoke failed: .tool-versions was not refreshed" >&2
    exit 1
fi

podman run --rm "$IMAGE_SSHD_REF" true
podman run --rm "$IMAGE_SSHD_REF" shell -lc 'echo sshd-shell-ok'
podman run --rm "$IMAGE_SSHD_REF" sh -lc 'test "$(id -u)" -eq 1000'

cid="$(podman run -d -p 2222:2222 "$IMAGE_SSHD_REF")"
trap 'podman rm -f "$cid" >/dev/null 2>&1 || true; rm -rf "$tmp" "$home_tmp"' EXIT
sleep 2
podman logs "$cid"
podman exec "$cid" test -f /etc/ssh/hostkeys/ssh_host_ed25519_key
podman exec "$cid" test -f /etc/ssh/hostkeys/ssh_host_rsa_key
podman exec "$cid" sh -lc 'passwd -S agent | grep -q " NP "'

echo "Podman smoke checks passed"
