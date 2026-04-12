# Shared setup for run scripts. Source this from bash, don't execute it.
# Provides: ROOT_DIR, IMAGE, HOME_VOL, RUNTIME, RUNTIME_ARGS array
#
# Environment overrides:
#   CONTAINER_RUNTIME  podman (default), docker, or msb
#   IMAGE              image name (default: agent-sandbox)
#   HOME_VOL           persistent home directory path

[[ -n "${BASH_SOURCE[0]:-}" ]] || { echo "common.sh must be sourced from bash" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RUNTIME="${CONTAINER_RUNTIME:-podman}"
IMAGE="${IMAGE:-agent-sandbox}"
HOME_VOL="${HOME_VOL:-${ROOT_DIR}/home}"

if [[ ! -d "$HOME_VOL" ]]; then
    echo "No persistent home at $HOME_VOL"
    echo "Run ./skeleton/init.sh first, or set HOME_VOL to your volume path."
    return 1 2>/dev/null || exit 1
fi

# API keys — forward all provider keys so any agent works from any entry point.
# -e VAR without =value only forwards if set on the host; unset vars are skipped.
API_KEY_ARGS=()
[[ -n "${ANTHROPIC_API_KEY:-}" ]]  && API_KEY_ARGS+=(-e ANTHROPIC_API_KEY)
[[ -n "${OPENAI_API_KEY:-}" ]]     && API_KEY_ARGS+=(-e OPENAI_API_KEY)
[[ -n "${GEMINI_API_KEY:-}" ]]     && API_KEY_ARGS+=(-e GEMINI_API_KEY)
[[ -n "${GOOGLE_API_KEY:-}" ]]     && API_KEY_ARGS+=(-e GOOGLE_API_KEY)

# Container runtime args — shared defaults with hardening
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
