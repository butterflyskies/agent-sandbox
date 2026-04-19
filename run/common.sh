# Shared setup for run scripts. Source this from bash, don't execute it.
# Provides: ROOT_DIR, IMAGE, HOME_VOL, RUNTIME, RUNTIME_ARGS array
#
# Environment overrides:
#   CONTAINER_RUNTIME  podman (default), docker, or msb
#   IMAGE              image name (default: agent-sandbox)
#   HOME_VOL           persistent home directory path

[[ -n "${BASH_SOURCE[0]:-}" ]] || { echo "common.sh must be sourced from bash" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(dirname "$SCRIPT_DIR")}"

RUNTIME="${CONTAINER_RUNTIME:-podman}"
IMAGE="${IMAGE:-agent-sandbox}"
HOME_VOL="${HOME_VOL:-${ROOT_DIR}/home}"

if [[ ! -d "$HOME_VOL" ]]; then
    echo "No persistent home at $HOME_VOL"
    echo "Run 'just init' first, or set HOME_VOL to your volume path."
    return 1 2>/dev/null || exit 1
fi

# API keys — forward all provider keys so any agent works from any entry point.
# Only forward vars that are set on the host.
API_KEY_NAMES=(ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY)
API_KEY_ARGS=()
for _key in "${API_KEY_NAMES[@]}"; do
    [[ -n "${!_key:-}" ]] || continue
    if [[ "$RUNTIME" == "msb" ]]; then
        # msb requires explicit values: -e VAR=value
        API_KEY_ARGS+=(-e "${_key}=${!_key}")
    else
        # podman/docker: -e VAR forwards from host environment
        API_KEY_ARGS+=(-e "$_key")
    fi
done

# Container runtime args — built per-runtime since CLIs differ significantly.
if [[ "$RUNTIME" == "msb" ]]; then
    # microsandbox: microVM-based, security handled at hypervisor level.
    RUNTIME_ARGS=(
        -t
        -v "${HOME_VOL}:/home/agent"
        "${API_KEY_ARGS[@]}"
    )
else
    # podman / docker: OCI container runtime with kernel-level hardening.
    RUNTIME_ARGS=(
        -it --rm
        --cap-drop=ALL
        --security-opt=no-new-privileges
        --read-only
        --tmpfs /tmp:rw,noexec,nosuid
        --hostname agent-sandbox
        -v "${HOME_VOL}:/home/agent:z"
        "${API_KEY_ARGS[@]}"
    )
fi

# Run a command inside the sandbox, abstracting runtime CLI differences.
# Usage: sandbox_exec <command> [args...]
sandbox_exec() {
    local cmd="$1"; shift
    if [[ "$RUNTIME" == "msb" ]]; then
        exec msb run "${RUNTIME_ARGS[@]}" "$IMAGE" -- "$cmd" "$@"
    else
        exec "$RUNTIME" run "${RUNTIME_ARGS[@]}" --entrypoint "$cmd" "$IMAGE" "$@"
    fi
}
