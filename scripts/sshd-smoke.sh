#!/usr/bin/env bash
set -euo pipefail

runtime="${CONTAINER_RUNTIME:-podman}"
image_ref="${IMAGE_SSHD_REF:-agent-sandbox-sshd:latest}"

for command in "$runtime" ssh ssh-keygen ssh-keyscan; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "sshd smoke: required command not found: $command" >&2
        exit 1
    fi
done

tmp="$(mktemp -d)"
cid=""
cleanup() {
    if [[ -n "$cid" ]]; then
        "$runtime" rm -f "$cid" >/dev/null 2>&1 || true
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT

ssh-keygen -q -N "" -t ed25519 -f "$tmp/id_ed25519"
cp "$tmp/id_ed25519.pub" "$tmp/authorized_keys"
chmod 0600 "$tmp/id_ed25519" "$tmp/authorized_keys"

volume_suffix=":ro"
if [[ "$runtime" == "podman" ]]; then
    volume_suffix=":ro,Z"
fi

# Mount /run as tmpfs to verify the entrypoint recreates /run/sshd at runtime.
cid="$(
    "$runtime" run -d \
        --tmpfs /run:rw,nosuid,nodev,size=64m \
        -p 127.0.0.1::2222 \
        -v "$tmp/authorized_keys:/etc/ssh/authorized_keys/agent${volume_suffix}" \
        "$image_ref"
)"

port="$("$runtime" port "$cid" 2222/tcp | head -n1 | sed 's/.*://')"
if [[ -z "$port" || "$port" == "2222/tcp" ]]; then
    echo "sshd smoke: could not resolve published SSH port" >&2
    "$runtime" port "$cid" >&2 || true
    exit 1
fi

ready=0
for _ in $(seq 1 60); do
    if ssh-keyscan -p "$port" 127.0.0.1 >"$tmp/known_hosts" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 0.5
done
if [[ "$ready" -ne 1 ]]; then
    echo "sshd smoke: SSH daemon did not become ready" >&2
    "$runtime" logs "$cid" >&2 || true
    exit 1
fi

ssh_args=(
    -F /dev/null
    -p "$port"
    -i "$tmp/id_ed25519"
    -o BatchMode=yes
    -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=yes
    -o "UserKnownHostsFile=$tmp/known_hosts"
)

ssh "${ssh_args[@]}" agent@127.0.0.1 \
    'test "$(id -u)" -eq 1000 &&
     test "$(stat -c %u "$HOME/.agent-sandbox")" -eq 1000 &&
     test -f "$HOME/.zshrc" &&
     cargo --version >/dev/null &&
     node --version >/dev/null &&
     codex --version >/dev/null &&
     gemini --version >/dev/null'

effective_config="$(
    "$runtime" exec "$cid" \
        /usr/sbin/sshd -T \
        -C user=agent,host=localhost,addr=127.0.0.1 \
        -f /etc/ssh/sshd_config
)"
grep -qx 'passwordauthentication no' <<<"$effective_config"
grep -qx 'kbdinteractiveauthentication no' <<<"$effective_config"
grep -qx 'permitemptypasswords no' <<<"$effective_config"
grep -qx 'authenticationmethods publickey' <<<"$effective_config"

echo "SSH variant connection smoke passed"
