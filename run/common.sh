# Shared setup for run scripts. Source this from bash, don't execute it.
# Provides: ROOT_DIR, IMAGE, HOME_VOL, RUNTIME, RUNTIME_ARGS array
#
# Environment overrides:
#   CONTAINER_RUNTIME  podman (default), docker, or msb
#   IMAGE              image name (default: agent-sandbox)
#   HOME_VOL           persistent home directory path (optional; ephemeral if unset/missing)
#   MSB_CPUS           override CPU count for msb (default: nproc/2, min 2)
#   MSB_MEMORY         override memory for msb (default: MemTotal/2, min 2G)

[[ -n "${BASH_SOURCE[0]:-}" ]] || { echo "common.sh must be sourced from bash" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(dirname "$SCRIPT_DIR")}"

RUNTIME="${CONTAINER_RUNTIME:-podman}"
IMAGE="${IMAGE:-agent-sandbox}"
HOME_VOL="${HOME_VOL:-${ROOT_DIR}/home}"

# API keys — forward all provider keys so any agent works from any entry point.
declare -A API_KEY_HOSTS=(
    [ANTHROPIC_API_KEY]="api.anthropic.com"
    [OPENAI_API_KEY]="api.openai.com"
    [GEMINI_API_KEY]="generativelanguage.googleapis.com"
    [GOOGLE_API_KEY]="*.googleapis.com"
)
API_KEY_NAMES=(ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY)
API_KEY_ARGS=()
for _key in "${API_KEY_NAMES[@]}"; do
    [[ -n "${!_key:-}" ]] || continue
    if [[ "$RUNTIME" == "msb" ]]; then
        _host="${API_KEY_HOSTS[$_key]:-}"
        if [[ -n "$_host" ]]; then
            API_KEY_ARGS+=(--secret "${_key}=${!_key}@${_host}")
        else
            API_KEY_ARGS+=(-e "${_key}=${!_key}")
        fi
    else
        API_KEY_ARGS+=(-e "$_key")
    fi
done

# Container runtime args — built per-runtime since CLIs differ significantly.
if [[ "$RUNTIME" == "msb" ]]; then
    # Compute resource allocation: half of host resources, with minimums.
    # MSB_CPUS / MSB_MEMORY override auto-detection; overrides skip the info line.
    if [[ -z "${MSB_CPUS:-}" && -z "${MSB_MEMORY:-}" ]]; then
        cpus=$(( $(nproc) / 2 ))
        [[ "$cpus" -ge 2 ]] || cpus=2
        _mem_raw=$(awk '/MemTotal/{print int($2/1024/1024/2)}' /proc/meminfo)
        [[ "$_mem_raw" -ge 2 ]] || _mem_raw=2
        memory="${_mem_raw}G"
        echo "agent-sandbox: allocating ${cpus} CPUs, ${memory} memory" >&2
    else
        cpus="${MSB_CPUS:-$(( $(nproc) / 2 ))}"
        [[ "$cpus" -ge 2 ]] || cpus=2
        memory="${MSB_MEMORY:-$(( $(awk '/MemTotal/{print int($2/1024/1024/2)}' /proc/meminfo) ))G}"
    fi

    RUNTIME_ARGS=(
        -t
        --shell /bin/zsh
        -c "$cpus"
        -m "$memory"
        --network-policy public-only
        --on-secret-violation block-and-log
        --tmpfs /tmp
        --tmpfs /var/tmp
        --tmpfs /run
        "${API_KEY_ARGS[@]}"
    )
    # Only mount HOME_VOL if it exists or was explicitly set.
    if [[ -d "$HOME_VOL" ]]; then
        RUNTIME_ARGS+=(-v "${HOME_VOL}:/home/agent")
    fi
else
    RUNTIME_ARGS=(
        -it
        --cap-drop=ALL
        --security-opt=no-new-privileges
        --read-only
        --tmpfs /tmp:rw,noexec,nosuid
        --tmpfs /var/tmp:rw,noexec,nosuid
        --tmpfs /run:rw,noexec,nosuid
        --hostname agent-sandbox
        "${API_KEY_ARGS[@]}"
    )
    if [[ -d "$HOME_VOL" ]]; then
        RUNTIME_ARGS+=(--rm -v "${HOME_VOL}:/home/agent:z")
    fi
fi

sandbox_exec() {
    local cmd="$1"; shift
    if [[ "$RUNTIME" == "msb" ]]; then
        exec msb run "${RUNTIME_ARGS[@]}" --entrypoint "$cmd" "$IMAGE" "$@"
    else
        exec "$RUNTIME" run "${RUNTIME_ARGS[@]}" --entrypoint "$cmd" "$IMAGE" "$@"
    fi
}
